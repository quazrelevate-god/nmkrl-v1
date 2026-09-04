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
from database import get_db
from utils import now_iso, serialize_issue
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


def _authorize(conn, row, coordinator: str):
    """Gate a state-changing action on a grievance.

    ``coordinator`` is optional so that builds already in the field — which
    send nothing for escalate/close/redirect/transfer — keep working. When it
    IS supplied (every current client build does), it must name a real account
    and that account must either own the grievance or be claiming an
    unassigned one. Without this, any caller could drive any grievance through
    its whole lifecycle.
    """
    who = (coordinator or "").strip().lower()
    if not who:
        return
    _reject_if_disabled(conn, who)
    if not _known_coordinator(conn, who):
        raise HTTPException(
            status_code=400,
            detail=f"Unknown coordinator '{who}'.",
        )
    owner = (row["assigned_coordinator"] or "").strip().lower()
    if owner and owner != who:
        raise HTTPException(
            status_code=403,
            detail=f"This grievance is assigned to @{owner}.",
        )


@router.get("/ward/{ward_no}")
def coordinator_ward_issues(
    ward_no: int,
    coordinator: str = Query(""),
    sort: str = Query("recent"),
    conn=Depends(get_db),
):
    """Ward grievances scoped for `coordinator`:
       — unassigned grievances (any status) — anyone can verify them
       — grievances assigned to <coordinator>
       — hides grievances assigned to another coordinator
    """
    order = "upvotes DESC, created_at DESC" if sort == "priority" else "created_at DESC"
    if coordinator:
        _reject_if_disabled(conn, coordinator)
        rows = conn.execute(
            f"""SELECT * FROM issues
                WHERE ward_no = ?
                  AND (assigned_coordinator = '' OR assigned_coordinator IS NULL
                       OR assigned_coordinator = ?)
                ORDER BY {order}""",
            (ward_no, coordinator.strip().lower()),
        ).fetchall()
    else:
        rows = conn.execute(
            f"SELECT * FROM issues WHERE ward_no = ? ORDER BY {order}",
            (ward_no,),
        ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/mine/{coordinator}")
def coordinator_my_reports(coordinator: str, conn=Depends(get_db)):
    """Every grievance a coordinator has taken ownership of, across all wards.
    Used by the mobile ward dropdown to show a per-ward assigned count."""
    rows = conn.execute(
        """SELECT * FROM issues WHERE assigned_coordinator = ?
           ORDER BY created_at DESC""",
        (coordinator.strip().lower(),),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.post("/issues/{issue_id}/verify")
def coord_verify(
    issue_id: str,
    coordinator: str = Form(...),
    conn=Depends(get_db),
):
    """Coordinator takes ownership: any → ACTIVE. Sets assigned_coordinator
    so the ticket vanishes from every other coordinator's ward tab."""
    prev = _load(conn, issue_id)
    _reject_if_disabled(conn, coordinator)
    if not _known_coordinator(conn, coordinator):
        raise HTTPException(
            status_code=400,
            detail=f"Unknown coordinator '{coordinator.strip().lower()}'.",
        )
    if (prev["assigned_coordinator"] or "").strip() not in ("", coordinator.strip().lower()):
        raise HTTPException(
            status_code=409,
            detail=f"Already assigned to @{prev['assigned_coordinator']}.",
        )
    conn.execute(
        """UPDATE issues
              SET status = 'ACTIVE', coordinator_message = '',
                  assigned_coordinator = ?,
                  assigned_at = COALESCE(assigned_at, ?)
            WHERE id = ?""",
        (coordinator.strip().lower(), now_iso(), issue_id),
    )
    audit.record(
        conn, issue_id, action="verify", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"], to_status="ACTIVE",
        note="Took ownership of the grievance.",
    )
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "assigned",
        f"Your grievance has been assigned to a coordinator.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/transfer")
async def coord_transfer(
    issue_id: str,
    department: str = Form(...),
    notes: str = Form(""),
    officer: str = Form(""),
    coordinator: str = Form(""),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Dept. Transfer: → FORWARDED with dept + responsible officer.

    The officer is now a COLUMN, not just a phrase inside the citizen-facing
    message — admin could not filter or count on a name buried in prose.
    """
    prev = _load(conn, issue_id)
    _authorize(conn, prev, coordinator)
    image_url, audio_url = await audit.store_evidence(photo, voice)
    if officer:
        msg = f"Routed to {department} — Responsible officer: {officer}."
    else:
        msg = f"Routed to {department} for inspection."
    if notes:
        msg += f" Note: {notes}"
    conn.execute(
        "UPDATE issues SET status = 'FORWARDED', department = ?, "
        "responsible_officer = ?, transferred_at = ?, "
        "coordinator_message = ? WHERE id = ?",
        (department, officer, now_iso(), msg, issue_id),
    )
    audit.record(
        conn, issue_id, action="transfer", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"], to_status="FORWARDED",
        note=notes, department=department, officer=officer,
        image_url=image_url, audio_url=audio_url,
    )
    row = _load(conn, issue_id)
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
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Escalate: → IN_PROGRESS + escalated_at now(). Mobile groups these into
    a dedicated 'Escalated' tab and keeps them out of 'My Reports'."""
    prev = _load(conn, issue_id)
    _authorize(conn, prev, coordinator)
    image_url, audio_url = await audit.store_evidence(photo, voice)
    conn.execute(
        """UPDATE issues
              SET status = 'IN_PROGRESS',
                  escalated_at = ?,
                  coordinator_message = ?
            WHERE id = ?""",
        (now_iso(),
         f"Escalated to higher authority. Reason: {description}",
         issue_id),
    )
    audit.record(
        conn, issue_id, action="escalate", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"], to_status="IN_PROGRESS",
        note=description, image_url=image_url, audio_url=audio_url,
    )
    row = _load(conn, issue_id)
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
    conn=Depends(get_db),
):
    """Redirect: → SUBMITTED with a delay-apology message."""
    prev = _load(conn, issue_id)
    _authorize(conn, prev, coordinator)
    msg = (
        "Sorry for the delay, will re-assign another team to resolve this issue faster. "
        f"Reason: {description}"
    )
    conn.execute(
        "UPDATE issues SET status = 'SUBMITTED', coordinator_message = ? WHERE id = ?",
        (msg, issue_id),
    )
    audit.record(
        conn, issue_id, action="redirect", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"], to_status="SUBMITTED",
        note=description,
    )
    row = _load(conn, issue_id)
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
async def coord_close(
    issue_id: str,
    notes: str = Form(""),
    coordinator: str = Form(""),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Close: → PENDING_VERIFICATION (citizen sees the verify/reject prompt).

    The coordinator app will not let a ticket be closed without a live photo
    and a voice note ("Live photo + voice note required to close"), so the
    proof of work arrives here and is stored on both the event and the issue.
    """
    prev = _load(conn, issue_id)
    _authorize(conn, prev, coordinator)
    image_url, audio_url = await audit.store_evidence(photo, voice)
    conn.execute(
        "UPDATE issues SET status = 'PENDING_VERIFICATION', notify_reporter = 1, "
        "closed_at = ?, coordinator_message = ?, "
        "closure_image_url = COALESCE(?, closure_image_url), "
        "closure_audio_url = COALESCE(?, closure_audio_url) WHERE id = ?",
        (now_iso(),
         notes or "Coordinator has closed this ticket. Please verify the resolution.",
         image_url, audio_url, issue_id),
    )
    audit.record(
        conn, issue_id, action="close", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"],
        to_status="PENDING_VERIFICATION", note=notes,
        image_url=image_url, audio_url=audio_url,
    )
    row = _load(conn, issue_id)
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
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Mark false: → FALSE with the coordinator's reason. Also records
    ownership so it lands in the acting coordinator's Previous tab."""
    prev = _load(conn, issue_id)
    _authorize(conn, prev, coordinator)
    image_url, audio_url = await audit.store_evidence(photo, voice)
    msg = f"Marked as false petition. Reason: {reason}" + (f" — {details}" if details else "")
    if coordinator:
        conn.execute(
            "UPDATE issues SET status = 'FALSE', coordinator_message = ?, "
            "assigned_coordinator = ? WHERE id = ?",
            (msg, coordinator.strip().lower(), issue_id),
        )
    else:
        conn.execute(
            "UPDATE issues SET status = 'FALSE', coordinator_message = ? WHERE id = ?",
            (msg, issue_id),
        )
    audit.record(
        conn, issue_id, action="mark_false", actor_type="coordinator",
        actor_id=coordinator, from_status=prev["status"], to_status="FALSE",
        note=f"{reason}{' — ' + details if details else ''}",
        image_url=image_url, audio_url=audio_url,
    )
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "false",
        "Your grievance was marked as a false petition.",
    )
    return serialize_issue(row)


@router.get("/issues/{issue_id}/timeline")
def coord_timeline(issue_id: str, conn=Depends(get_db)):
    """Everything that has happened to a grievance, oldest first.

    `issues.coordinator_message` only ever holds the LAST note written, so this
    is the only way to see the transfer note that a later escalate overwrote,
    or the photo/voice a coordinator recorded when they closed the ticket.
    """
    _load(conn, issue_id)  # 404 for an unknown grievance
    return {"issue_id": issue_id, "events": audit.timeline(conn, issue_id)}
