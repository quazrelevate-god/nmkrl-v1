"""
routers/coordinator.py
----------------------
Coordinator-facing endpoints. Every write records the acting coordinator's
username on the issue (assigned_coordinator) so the mobile app's tabs can
partition correctly across accounts and the citizen gets the right push.

  POST /api/coordinator/issues/{id}/verify   → any → ACTIVE
                                               (owner = form 'coordinator';
                                               citizen sees "Assigned")
  POST /api/coordinator/issues/{id}/transfer → → FORWARDED (dept transfer)
  POST /api/coordinator/issues/{id}/escalate → → IN_PROGRESS + escalated_at now()
                                               (mobile groups under Escalated)
  POST /api/coordinator/issues/{id}/redirect → → SUBMITTED with delay-apology
  POST /api/coordinator/issues/{id}/close    → → PENDING_VERIFICATION
  POST /api/coordinator/issues/{id}/mark_false → → FALSE

  GET  /api/coordinator/issues/{id}/timeline → append-only action history

  GET  /api/coordinator/ward/{n}
       ?coordinator=<username>       required — filters ownership properly
       ?sort=recent|priority         optional — created_at desc / upvotes desc
    Returns:
       • unassigned open grievances (any coordinator may verify)
       • grievances assigned TO <coordinator> (in every state)
       • hides grievances assigned to a DIFFERENT coordinator
"""

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile

import audit
import duplicates
from database import get_db
from session_auth import coordinator_session, require_same_coordinator
import corporations
from utils import has_reporter, haversine_m, now_iso, public_issue, serialize_issue
from routers.notifications import emit_status_change

router = APIRouter(prefix="/api/coordinator", tags=["coordinator"])


def _load(conn, issue_id):
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    return row


def _known_coordinator(conn, username: str) -> bool:
    """Is this a real account in the admin-managed coordinators table?"""
    return conn.execute(
        "SELECT 1 FROM coordinators WHERE LOWER(username) = ?",
        (username.strip().lower(),),
    ).fetchone() is not None


def _reject_if_disabled(conn, username: str) -> None:
    """Stop a revoked account mid-session.

    Sessions do not expire, so gating only the login would leave a disabled
    coordinator working until they happened to sign out. Every action checks
    instead, which makes the admin console's disable take effect on the next
    tap rather than the next login.
    """
    row = conn.execute(
        "SELECT status FROM coordinators WHERE LOWER(username) = ?",
        ((username or "").strip().lower(),),
    ).fetchone()
    if row is not None and (row["status"] or "active").lower() != "active":
        raise HTTPException(
            status_code=403,
            detail="This account has been disabled. Contact the MLA office.",
        )


def display_name(conn, username: str) -> str:
    """A coordinator's name as people know it. The username is an internal,
    auto-generated key (e.g. "arunkumarddfa") that no screen shows."""
    who = (username or "").strip().lower()
    row = conn.execute(
        "SELECT name FROM coordinators WHERE LOWER(username) = ?", (who,)
    ).fetchone() if who else None
    return (row["name"] if row is not None and row["name"] else who) or "another coordinator"


def _taken_by(conn, owner: str) -> HTTPException:
    return HTTPException(
        status_code=409,
        detail=f"{display_name(conn, owner)} has already taken this grievance.",
    )


def _in_scope(conn, row, who: str) -> bool:
    """Is this grievance in the coordinator's own corporation and constituency?

    Grievance ids are public (the ward feed lists them), so an action must not
    be accepted just because the caller knows one. A coordinator whose
    constituency does not resolve is limited to their home ward.
    """
    me = conn.execute(
        "SELECT constituency, home_ward FROM coordinators WHERE LOWER(username) = ?",
        ((who or "").strip().lower(),),
    ).fetchone()
    if me is None or row is None:
        return False
    corp = corporations.corporation_of_constituency(me["constituency"])
    if corp is None:
        return str(row["ward_no"]) == str(me["home_ward"] or "").strip()
    if (row["corporation"] or corporations.LEGACY_CORPORATION) != corp:
        return False
    wards = corporations.ac_map(corp).get((me["constituency"] or "").strip(), [])
    return str(row["ward_no"]) in wards


def _require_scope(conn, row, who: str) -> None:
    """404 for a grievance outside the coordinator's constituency — answered like
    one that does not exist, as the MLA office console does (tenancy.load_issue)."""
    if not _in_scope(conn, row, who):
        raise HTTPException(status_code=404, detail="Issue not found")


def _authorize(conn, row, coordinator: str):
    """Gate a state-changing action on a grievance: a real, active account,
    acting inside its own constituency, on a grievance that is unowned or its
    own. This is the fast, friendly pre-check; `_take` repeats the ownership
    and status test atomically when it writes.
    """
    who = (coordinator or "").strip().lower()
    _reject_if_disabled(conn, who)
    if not _known_coordinator(conn, who):
        raise HTTPException(
            status_code=400,
            detail=f"Unknown coordinator '{who}'.",
        )
    _require_scope(conn, row, who)
    owner = (row["assigned_coordinator"] or "").strip().lower()
    if owner and owner != who:
        raise _taken_by(conn, owner)


def _take(conn, issue_id: str, who: str, allowed: tuple, action: str,
          sets: str, params: tuple = ()):
    """Apply an action and make `who` the owner — in ONE conditional UPDATE.

    Checking ownership and status in Python and then writing let two
    coordinators both "win" the same grievance: both passed the check, both got
    success, the last write silently took it, and the citizen was told twice.
    Here the database applies the change only while the grievance is still
    unowned (or already `who`'s) and still in an allowed status; the loser gets
    409 with who took it. assigned_at moves only when the owner changes.
    """
    who = (who or "").strip().lower()
    marks = ",".join("?" for _ in allowed)
    cur = conn.execute(
        f"""UPDATE issues
               SET {sets},
                   assigned_at = CASE WHEN COALESCE(assigned_coordinator, '') = ?
                                      THEN assigned_at ELSE ? END,
                   assigned_coordinator = ?
             WHERE id = ?
               AND COALESCE(assigned_coordinator, '') IN ('', ?)
               AND status IN ({marks})""",
        (*params, who, now_iso(), who, issue_id, who, *allowed),
    )
    if cur.rowcount == 1:
        return _load(conn, issue_id)
    now = _load(conn, issue_id)
    owner = (now["assigned_coordinator"] or "").strip().lower()
    if owner and owner != who:
        raise _taken_by(conn, owner)
    _require_status(now, allowed, action)
    raise HTTPException(status_code=409, detail="This grievance just changed. Refresh and try again.")


# The lifecycle the coordinator app drives:
#   SUBMITTED → ACTIVE → (FORWARDED | IN_PROGRESS) → PENDING_VERIFICATION → CLOSED
#   any assigned state → FALSE (terminal)
# CLOSED and FALSE are terminal: nothing a coordinator does may move them, and a
# ticket already awaiting the citizen's verdict (PENDING_VERIFICATION) is theirs
# to approve or reject, not the coordinator's to re-drive. The mobile app already
# hides the buttons for these states — terminal tickets render in the buttonless
# "Resolved" tab and PENDING_VERIFICATION shows a disabled chip — but that guard
# is only as fresh as the last 15s poll. A stale card, a double-tap retry, or any
# non-app client can still send the transition, so it must be rejected HERE too.
# Admin actions already guard this way (routers/admin.py); the coordinator ones
# did not, which let a CLOSED ticket be re-closed or a FALSE one transferred.
def _require_status(prev, allowed, action: str) -> None:
    status = (prev["status"] or "").strip().upper()
    if status not in allowed:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot {action} a grievance that is {status or 'in an unknown state'}.",
        )


@router.get("/me")
def coordinator_me(
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """The signed-in coordinator's current profile.

    The app caches the profile it received at sign-in, so anything the MLA
    office changed afterwards — a new photo, a moved home ward, a renamed role —
    never reached the phone until the coordinator happened to sign out and in
    again. The app re-reads this on open and on resume instead.
    """
    from routers.auth import coordinator_profile

    row = conn.execute(
        "SELECT * FROM coordinators WHERE LOWER(username) = ?", (session_username,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Coordinator not found.")
    return coordinator_profile(row)


@router.get("/ward/{ward_no}")
def coordinator_ward_issues(
    ward_no: int,
    coordinator: str = Query(""),
    sort: str = Query("recent"),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Ward grievances scoped for `coordinator`:
       — unassigned grievances (any status) — anyone can verify them
       — grievances assigned to <coordinator>
       — hides grievances assigned to another coordinator
    """
    coordinator = require_same_coordinator(session_username, coordinator)
    order = "upvotes DESC, created_at DESC" if sort == "priority" else "created_at DESC"
    # The live corporation's ward: ward numbers repeat across corporations, and
    # a signed-in coordinator is always in the live one (session_auth).
    corp = corporations.active_id(conn)
    _reject_if_disabled(conn, coordinator)
    # Only the coordinator's own constituency: this list carries reporters'
    # names and phone numbers.
    _require_scope(conn, {"ward_no": ward_no, "corporation": corp}, coordinator)
    rows = conn.execute(
        f"""SELECT * FROM issues
            WHERE ward_no = ? AND corporation = ? AND status <> 'MERGED'
              AND (assigned_coordinator = '' OR assigned_coordinator IS NULL
                   OR assigned_coordinator = ?)
            ORDER BY {order}""",
        (ward_no, corp, coordinator.strip().lower()),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/mine/{coordinator}")
def coordinator_my_reports(
    coordinator: str,
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Every grievance a coordinator has taken ownership of, across all wards.
    Used by the mobile ward dropdown to show a per-ward assigned count."""
    coordinator = require_same_coordinator(session_username, coordinator)
    # A merged grievance is no longer anyone's work item: its reporter follows
    # the original now, and every action on it is refused.
    rows = conn.execute(
        """SELECT * FROM issues WHERE assigned_coordinator = ? AND status <> 'MERGED'
           ORDER BY created_at DESC""",
        (coordinator.strip().lower(),),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/constituency")
def coordinator_constituency_issues(
    coordinator: str = Query(""),
    sort: str = Query("recent"),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Every grievance across the signed-in coordinator's whole CONSTITUENCY —
    the browse surface for the mobile list.

    A coordinator is still assigned one home ward in the admin console, and that
    ward stays their priority: it is where their new-grievance notifications go
    (see routers/notifications.emit_new_grievance, deliberately ward-locked).
    But the list is no longer confined to it — any coordinator in the AC can see
    every grievance in the AC and claim any of them, so the MLA can point anyone
    at anything. This returns:
       — unassigned grievances in ANY of the AC's wards (anyone may verify)
       — grievances assigned to THIS coordinator (any ward)
       — hides grievances assigned to a DIFFERENT coordinator
    plus `wards` (the AC's ward list, for the app's ward filter) and `home_ward`
    (so the app can float the coordinator's own ward to the top).
    """
    coordinator = require_same_coordinator(session_username, coordinator)
    if not coordinator:
        raise HTTPException(status_code=400, detail="coordinator is required.")
    _reject_if_disabled(conn, coordinator)
    me = conn.execute(
        "SELECT constituency, home_ward FROM coordinators WHERE LOWER(username) = ?",
        (coordinator.strip().lower(),),
    ).fetchone()
    if me is None:
        raise HTTPException(status_code=404, detail="Unknown coordinator.")
    constituency = (me["constituency"] or "").strip()
    home_ward = (me["home_ward"] or "").strip()
    corp = corporations.corporation_of_constituency(constituency) or corporations.active_id(conn)
    wards = corporations.ac_map(corp).get(constituency, [])
    # Never widen to the whole city: if the stored AC name doesn't resolve, fall
    # back to the coordinator's own ward alone.
    if not wards:
        wards = [home_ward] if home_ward else []
    if not wards:
        return {"count": 0, "issues": [], "wards": [], "home_ward": home_ward,
                "constituency": constituency}

    order = "upvotes DESC, created_at DESC" if sort == "priority" else "created_at DESC"
    # Both conditions are written so the planner narrows by ward first. That is
    # the selective one: an AC is a few wards out of 200, while "unassigned"
    # is most of the city.
    #   * ward_no is stored INTEGER and the AC map holds ward strings, so the
    #     parameters are converted, not the column — CAST(ward_no AS TEXT) hid
    #     ward_no from every ward index.
    #   * The ownership test goes through COALESCE so it cannot be answered from
    #     idx_issues_assigned. Written as a bare OR, SQLite chose that index, looked
    #     up every unassigned grievance city-wide and threw away the other ACs'
    #     (~4 s at 500k rows vs ~270 ms this way, identical rows; ANALYZE does
    #     not change its mind).
    # `wards` stays as strings in the response for the app's ward filter.
    ward_nos = [int(w) for w in wards if str(w).strip().isdigit()]
    if not ward_nos:
        return {"count": 0, "issues": [], "wards": wards, "home_ward": home_ward,
                "constituency": constituency}
    placeholders = ",".join("?" for _ in ward_nos)
    rows = conn.execute(
        f"""SELECT * FROM issues
             WHERE ward_no IN ({placeholders}) AND corporation = ?
               AND status <> 'MERGED'
               AND COALESCE(assigned_coordinator, '') IN ('', ?)
             ORDER BY {order}""",
        [*ward_nos, corp, coordinator.strip().lower()],
    ).fetchall()
    return {
        "count": len(rows),
        "issues": [serialize_issue(r) for r in rows],
        "wards": wards,
        "home_ward": home_ward,
        "constituency": constituency,
    }


@router.post("/issues/{issue_id}/verify")
def coord_verify(
    issue_id: str,
    coordinator: str = Form(...),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Coordinator takes ownership ("Assign Grievance").

    A fresh or redirected report (SUBMITTED) becomes ACTIVE. An unowned
    grievance already in flight — forwarded or escalated by the MLA office, or
    released from a disabled coordinator — keeps its status and just gains an
    owner; refusing those left cards in every Open tab whose button always
    failed. Ownership is taken atomically (see `_take`).
    """
    prev = _load(conn, issue_id)
    coordinator = require_same_coordinator(session_username, coordinator)
    who = coordinator.strip().lower()
    _authorize(conn, prev, who)
    was_mine = (prev["assigned_coordinator"] or "").strip().lower() == who
    if was_mine and prev["status"] != "SUBMITTED":
        return serialize_issue(prev)  # re-tap by the owner: nothing to do
    row = _take(
        conn, issue_id, who, ("SUBMITTED", "ACTIVE", "FORWARDED", "IN_PROGRESS"),
        "assign",
        "status = CASE WHEN status = 'SUBMITTED' THEN 'ACTIVE' ELSE status END, "
        "coordinator_message = CASE WHEN status = 'SUBMITTED' THEN '' ELSE coordinator_message END",
    )
    audit.record(
        conn, issue_id, action="verify", actor_type="coordinator",
        actor_id=who, from_status=prev["status"], to_status=row["status"],
        note="Took ownership of the grievance.",
    )
    emit_status_change(
        conn, row, "assigned",
        "Your grievance has been assigned to a coordinator.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/transfer")
async def coord_transfer(
    issue_id: str,
    department: str = Form(...),
    notes: str = Form(""),
    officer: str = Form(""),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Dept. Transfer: → FORWARDED with dept + responsible officer.

    The officer is now a COLUMN, not just a phrase inside the citizen-facing
    message — admin could not filter or count on a name buried in prose.
    The acting coordinator becomes the owner, so the work is credited to them
    and a later citizen rejection reaches them. A transfer supersedes an
    escalation, so escalated_at is cleared (it kept FORWARDED tickets in the
    Escalated tab).
    """
    prev = _load(conn, issue_id)
    who = require_same_coordinator(session_username, coordinator)
    _authorize(conn, prev, who)
    # A re-transfer (FORWARDED→FORWARDED) is allowed to correct the department.
    # Blocked once closed/false or awaiting the citizen.
    allowed = ("ACTIVE", "FORWARDED", "IN_PROGRESS")
    _require_status(prev, allowed, "transfer")
    image_url, audio_url = await audit.store_evidence(photo, voice)
    if officer:
        msg = f"Routed to {department} — Responsible officer: {officer}."
    else:
        msg = f"Routed to {department} for inspection."
    if notes:
        msg += f" Note: {notes}"
    row = _take(
        conn, issue_id, who, allowed, "transfer",
        "status = 'FORWARDED', department = ?, responsible_officer = ?, "
        "transferred_at = ?, escalated_at = NULL, coordinator_message = ?",
        (department, officer, now_iso(), msg),
    )
    audit.record(
        conn, issue_id, action="transfer", actor_type="coordinator",
        actor_id=who, from_status=prev["status"], to_status="FORWARDED",
        note=notes, department=department, officer=officer,
        image_url=image_url, audio_url=audio_url,
    )
    emit_status_change(
        conn, row, "transfer",
        f"Your grievance was transferred to {department}.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/escalate")
async def coord_escalate(
    issue_id: str,
    description: str = Form(...),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Escalate: → IN_PROGRESS + escalated_at now(). Mobile groups these into
    a dedicated 'Escalated' tab and keeps them out of 'My Reports'."""
    prev = _load(conn, issue_id)
    who = require_same_coordinator(session_username, coordinator)
    _authorize(conn, prev, who)
    allowed = ("ACTIVE", "FORWARDED", "IN_PROGRESS")
    _require_status(prev, allowed, "escalate")
    image_url, audio_url = await audit.store_evidence(photo, voice)
    row = _take(
        conn, issue_id, who, allowed, "escalate",
        "status = 'IN_PROGRESS', escalated_at = ?, coordinator_message = ?",
        (now_iso(), f"Escalated to higher authority. Reason: {description}"),
    )
    audit.record(
        conn, issue_id, action="escalate", actor_type="coordinator",
        actor_id=who, from_status=prev["status"], to_status="IN_PROGRESS",
        note=description, image_url=image_url, audio_url=audio_url,
    )
    emit_status_change(
        conn, row, "escalated",
        "Your grievance was escalated to a higher authority.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/redirect")
def coord_redirect(
    issue_id: str,
    description: str = Form(...),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Redirect: → SUBMITTED, back in the ward pool, with a delay-apology.

    The grievance is released: it used to keep its owner, so nobody else could
    take it while the citizen was told another team would.
    """
    prev = _load(conn, issue_id)
    who = require_same_coordinator(session_username, coordinator)
    _authorize(conn, prev, who)
    allowed = ("ACTIVE", "FORWARDED", "IN_PROGRESS")
    _require_status(prev, allowed, "redirect")
    msg = (
        "Sorry for the delay, will re-assign another team to resolve this issue faster. "
        f"Reason: {description}"
    )
    marks = ",".join("?" for _ in allowed)
    cur = conn.execute(
        f"""UPDATE issues
               SET status = 'SUBMITTED', coordinator_message = ?,
                   assigned_coordinator = '', assigned_at = NULL, escalated_at = NULL
             WHERE id = ? AND COALESCE(assigned_coordinator, '') IN ('', ?)
               AND status IN ({marks})""",
        (msg, issue_id, who, *allowed),
    )
    if cur.rowcount != 1:
        raise HTTPException(status_code=409, detail="This grievance just changed. Refresh and try again.")
    audit.record(
        conn, issue_id, action="redirect", actor_type="coordinator",
        actor_id=who, from_status=prev["status"], to_status="SUBMITTED",
        note=description,
    )
    row = _load(conn, issue_id)
    # Every other coordinator action told the citizen; this one silently moved
    # their grievance backwards, so it looked like nothing had happened.
    emit_status_change(
        conn, row, "redirect",
        "Your grievance is being re-assigned to another team.",
    )
    try:
        from routers.notifications import emit_new_grievance
        emit_new_grievance(conn, row)
    except Exception:
        pass
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
async def coord_close(
    issue_id: str,
    notes: str = Form(""),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Close: → PENDING_VERIFICATION (citizen sees the verify/reject prompt).

    The coordinator app will not let a ticket be closed without a live photo
    and a voice note ("Live photo + voice note required to close"), so the
    proof of work arrives here and is stored on both the event and the issue.
    That requirement is now enforced HERE too: a resolution without evidence is
    the one thing the citizen's verify prompt and the admin audit both rely on,
    so the API must not accept a proofless close the app would never send. Only
    close carries this — transfer/escalate/mark_false keep evidence optional.

    A grievance with no citizen account behind it (logged at the MLA office,
    or the reporter deleted their account) has nobody to confirm, so it closes
    outright instead of waiting in PENDING_VERIFICATION forever.
    """
    prev = _load(conn, issue_id)
    who = require_same_coordinator(session_username, coordinator)
    _authorize(conn, prev, who)
    # Close only an in-flight ticket. Blocks re-closing something that is
    # already PENDING_VERIFICATION, CLOSED, or FALSE.
    allowed = ("ACTIVE", "FORWARDED", "IN_PROGRESS")
    _require_status(prev, allowed, "close")
    image_url, audio_url = await audit.store_evidence(photo, voice)
    if not image_url or not audio_url:
        missing = " and ".join(
            m for m, present in (("a photo", image_url), ("a voice note", audio_url))
            if not present
        )
        raise HTTPException(
            status_code=400,
            detail=f"A closure needs {missing} as proof the grievance was resolved.",
        )
    confirmable = has_reporter(conn, prev)
    to_status = "PENDING_VERIFICATION" if confirmable else "CLOSED"
    now = now_iso()
    row = _take(
        conn, issue_id, who, allowed, "close",
        # Store what the coordinator actually wrote — nothing if they wrote
        # nothing. The citizen's prompt to verify belongs in the notification,
        # not in this field. rejected_at is cleared: the rejection it recorded
        # has now been answered, and the "Rejected — review ASAP" badge must
        # not follow the grievance into its closed state.
        "status = ?, notify_reporter = ?, closed_at = ?, coordinator_message = ?, "
        "closure_image_url = ?, closure_audio_url = ?, rejected_at = NULL, "
        "resolved_at = CASE WHEN ? = 'CLOSED' THEN ? ELSE resolved_at END",
        (to_status, 1 if confirmable else 0, now, notes, image_url, audio_url,
         to_status, now),
    )
    audit.record(
        conn, issue_id, action="close", actor_type="coordinator",
        actor_id=who, from_status=prev["status"],
        to_status=to_status, note=notes,
        image_url=image_url, audio_url=audio_url,
    )
    emit_status_change(
        conn, row, "closed",
        "Your grievance is marked resolved — please approve or reject to confirm.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/mark_false")
async def coord_mark_false(
    issue_id: str,
    reason: str = Form(...),
    details: str = Form(""),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Mark false: → FALSE with the coordinator's reason. Also records
    ownership so it lands in the acting coordinator's Previous tab."""
    prev = _load(conn, issue_id)
    who = require_same_coordinator(session_username, coordinator)
    _authorize(conn, prev, who)
    # False can be flagged from the ward pool (SUBMITTED, the Open tab shows it)
    # or while assigned — but never on a resolved ticket or one the citizen is
    # already verifying.
    allowed = ("SUBMITTED", "ACTIVE", "FORWARDED", "IN_PROGRESS")
    _require_status(prev, allowed, "mark as false")
    image_url, audio_url = await audit.store_evidence(photo, voice)
    msg = f"Marked as false petition. Reason: {reason}" + (f" — {details}" if details else "")
    row = _take(
        conn, issue_id, who, allowed, "mark as false",
        "status = 'FALSE', coordinator_message = ?",
        (msg,),
    )
    audit.record(
        conn, issue_id, action="mark_false", actor_type="coordinator",
        actor_id=who, from_status=prev["status"], to_status="FALSE",
        note=f"{reason}{' — ' + details if details else ''}",
        image_url=image_url, audio_url=audio_url,
    )
    emit_status_change(
        conn, row, "false",
        f"Your grievance was marked as a false petition. Reason: {reason}",
    )
    return serialize_issue(row)


@router.get("/issues/{issue_id}/timeline")
def coord_timeline(
    issue_id: str,
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Everything that has happened to a grievance, oldest first.

    `issues.coordinator_message` only ever holds the LAST note written, so this
    is the only way to see the transfer note that a later escalate overwrote,
    or the photo/voice a coordinator recorded when they closed the ticket.
    """
    row = _load(conn, issue_id)  # 404 for an unknown grievance
    _require_scope(conn, row, session_username)
    return {"issue_id": issue_id, "events": audit.timeline(conn, issue_id)}


# ── Duplicates ───────────────────────────────────────────────────────────────
# The ward coordinator rules on duplicates alongside admin, through the same
# shared logic (duplicates.py), so the two cannot decide a case differently.
#
# One asymmetry is deliberate. The coordinator must be able to act on the CHILD
# — it is a grievance in their ward — but the PARENT can be anywhere: detection
# matches within 100m with no regard for ward boundaries, so the original is
# often in a neighbouring ward or already owned by someone else. They therefore
# get the parent PII-stripped: enough to judge whether it is the same problem
# (ticket, title, photo, distance, support) and nothing about the person who
# reported it.

#: Manual merges search wider than detection does. Detection is conservative
#: on purpose; a coordinator reaching for this has already seen with their own
#: eyes that two reports are the same thing.
MERGE_SEARCH_RADIUS_M = 300.0


def _may_act(conn, row, who: str) -> bool:
    """Could this coordinator take an action on this grievance?"""
    try:
        _authorize(conn, row, who)
        return True
    except HTTPException:
        return False


@router.get("/issues/{issue_id}/duplicate")
def coord_duplicate_context(
    issue_id: str,
    coordinator: str = Query(""),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """The suspected original, plus any reports already folded into this one."""
    coordinator = require_same_coordinator(session_username, coordinator)
    _reject_if_disabled(conn, coordinator)
    row = _load(conn, issue_id)
    _require_scope(conn, row, coordinator)
    mine = _may_act(conn, row, coordinator)
    return {
        "awaiting_review": duplicates.awaiting_review(row),
        "decision": row["duplicate_decision"] or "",
        "decided_by": row["duplicate_decided_by"] or "",
        "merged_into_id": row["merged_into_id"],
        "parent": duplicates.parent_preview(conn, row),
        "children": duplicates.merged_children(conn, issue_id, redact=not mine),
    }


@router.get("/issues/{issue_id}/merge-candidates")
def coord_merge_candidates(
    issue_id: str,
    coordinator: str = Query(""),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Open grievances near this one, for a merge the detector did not suggest.

    Detection only flags what it is fairly sure of, so a coordinator standing
    in front of two reports of the same overflowing bin needs a way to say so
    by hand. Results are PII-stripped for the same reason the parent preview
    is: they can legitimately span wards.
    """
    coordinator = require_same_coordinator(session_username, coordinator)
    _reject_if_disabled(conn, coordinator)
    row = _load(conn, issue_id)
    _require_scope(conn, row, coordinator)
    rows = conn.execute(
        """SELECT * FROM issues
            WHERE status IN ('SUBMITTED', 'ACTIVE', 'IN_PROGRESS', 'FORWARDED')
              AND id <> ? AND corporation = ?"""
        , (issue_id, row["corporation"] or corporations.LEGACY_CORPORATION),
    ).fetchall()
    out = []
    for cand in rows:
        dist = haversine_m(
            row["latitude"], row["longitude"],
            cand["latitude"], cand["longitude"],
        )
        if dist > MERGE_SEARCH_RADIUS_M:
            continue
        item = public_issue(cand)
        item["distance_m"] = round(dist, 1)
        item["same_ward"] = cand["ward_no"] == row["ward_no"]
        out.append(item)
    out.sort(key=lambda i: i["distance_m"])
    return {"count": len(out), "candidates": out}


@router.post("/issues/{issue_id}/merge")
def coord_merge(
    issue_id: str,
    parent_id: str = Form(...),
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Fold this grievance into the one it duplicates.

    The coordinator must be able to act on the child. The parent may belong to
    another coordinator, but it must be in this coordinator's constituency:
    folding a report into another office's ticket hands the citizen to an
    office that never saw it (the MLA console refuses the same).
    """
    coordinator = require_same_coordinator(session_username, coordinator)
    child = _load(conn, issue_id)
    _authorize(conn, child, coordinator)
    parent = _load(conn, parent_id)
    if not _in_scope(conn, parent, coordinator):
        raise HTTPException(
            status_code=409,
            detail="The original is in another constituency; it cannot be merged from here.",
        )
    return duplicates.merge(
        conn, child=child, parent=parent,
        actor_type="coordinator", actor_id=coordinator,
    )


@router.post("/issues/{issue_id}/keep-separate")
def coord_keep_separate(
    issue_id: str,
    coordinator: str = Form(""),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Rule that the flagged grievance is a different problem after all."""
    coordinator = require_same_coordinator(session_username, coordinator)
    child = _load(conn, issue_id)
    _authorize(conn, child, coordinator)
    return duplicates.keep_separate(
        conn, child=child, actor_type="coordinator", actor_id=coordinator,
    )
