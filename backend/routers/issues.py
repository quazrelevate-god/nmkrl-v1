"""
routers/issues.py
-----------------
Citizen-facing endpoints:
  * POST /api/issues/report         - report (saved instantly; Gemini + the
                                      100m duplicate check run in background)
  * POST /api/issues/{id}/upvote    - upvote (one per user)
  * GET  /api/issues/nearby         - issues within a radius (map view)
  * GET  /api/issues/history/{uid}  - a user's submissions, with any merged
                                      report shown as the grievance it joined
  * POST /api/issues/{id}/verify    - citizen approves/rejects a resolution

Nothing here asks the citizen about duplicates. Detection happens in the
background half of a report and is silent to them; admin and the ward
coordinator rule on it (see duplicates.py).
"""

import json

import os

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile

import audit
import boundaries
from database import get_connection, get_db
from session_auth import citizen_session, require_same_citizen
from gemini_service import ai_available, check_duplicate, classify_department, process_audio
from utils import (
    haversine_m,
    new_id,
    now_iso,
    public_issue,
    reverse_geocode,
    save_upload,
    serialize_issue,
    ticket_number,
    UPLOAD_DIR,
)

router = APIRouter(prefix="/api/issues", tags=["issues"])

# Single source of truth for the out-of-area refusal, so the API and the two
# clients cannot drift apart on the wording.
OUTSIDE_GCC_MESSAGE = (
    "Grievances outside GCC boundaries are not accepted right now."
)

DUPLICATE_RADIUS_M = 100.0
# Client sends this literal when the user hasn't typed a title — we replace
# it with the Gemini-generated title (or fall back if Gemini gave nothing).
_DEFAULT_TITLE_SENTINEL = "Street Issue"


def _nearby_open_issues(conn, lat: float, lng: float, radius_m: float) -> list[dict]:
    """Return all open issues within radius as dicts (for Gemini comparison)."""
    rows = conn.execute(
        "SELECT * FROM issues WHERE status IN ('SUBMITTED', 'ACTIVE', 'IN_PROGRESS')"
    ).fetchall()
    results = []
    for row in rows:
        dist = haversine_m(lat, lng, row["latitude"], row["longitude"])
        if dist <= radius_m:
            item = dict(row)
            item["distance_m"] = round(dist, 1)
            results.append(item)
    return results


def _finish_report(
    *, issue_id: str, audio_bytes, audio_mime: str, latitude: float,
    longitude: float, user_id: str, keep_title: bool,
) -> None:
    """Background half of a submission: transcribe, route, de-duplicate.

    Runs after the response is already sent (FastAPI runs a plain ``def`` task
    in a threadpool, so the blocking Gemini calls do not stall the event loop).
    Opens its own connection because the request's connection is long gone.

    None of this is ever reported to the citizen as a problem. A failed
    transcription and a suspected duplicate are both staff business: the
    failure is recorded so admin can retry it, and the duplicate flag waits for
    admin or the ward coordinator to rule on. The reporter just gets their
    grievance card.
    """
    problems = []
    try:
        ai = (process_audio(audio_bytes, mime_type=audio_mime)
              if audio_bytes else
              {"title": "", "transcript": "", "transcript_ta": "", "highlights": []})
    except Exception as exc:
        problems.append(f"Transcription failed: {exc}")
        ai = {"title": "", "transcript": "", "transcript_ta": "", "highlights": []}

    with get_connection() as conn:
        row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
        if row is None:
            return  # withdrawn before processing finished

        title = row["title"]
        gemini_title = (ai.get("title") or "").strip()
        if not keep_title and gemini_title:
            title = gemini_title
        transcript = ai.get("transcript", "") or ""
        transcript_ta = ai.get("transcript_ta", "") or ""
        highlights = ai.get("highlights", []) or []

        try:
            area_name = reverse_geocode(latitude, longitude)
        except Exception as exc:
            problems.append(f"Area lookup failed: {exc}")
            area_name = ""
        try:
            department = classify_department(title, transcript, highlights)
        except Exception as exc:
            problems.append(f"Department routing failed: {exc}")
            department = ""

        # Duplicate detection. With a Gemini key, ask the model whether this
        # report describes the same problem as an open one nearby (semantic).
        # Without a key — the deliberately AI-free path — fall back to a plain
        # proximity rule so the "already reported" experience still works: the
        # nearest OPEN grievance in the SAME ward within the radius is treated as
        # the likely original. Proximity alone over-merges, so it is used only
        # when the model cannot be consulted, never to override its judgement.
        dup_id = None
        try:
            nearby = [
                i for i in _nearby_open_issues(conn, latitude, longitude, DUPLICATE_RADIUS_M)
                if i["id"] != issue_id
            ]
            if nearby:
                if ai_available():
                    dup = check_duplicate(title, transcript, highlights, nearby)
                    dup_id = dup["id"] if dup else None
                else:
                    same_ward = [i for i in nearby if i.get("ward_no") == row["ward_no"]]
                    if same_ward:
                        dup_id = min(same_ward, key=lambda i: i["distance_m"])["id"]
        except Exception as exc:
            problems.append(f"Duplicate check failed: {exc}")
            dup_id = None

        conn.execute(
            """UPDATE issues
                  SET title = ?, transcript = ?, transcript_ta = ?,
                      summary_highlights = ?, area_name = ?, department = ?,
                      possible_duplicate_id = ?, processing = 0,
                      processing_error = ?
                WHERE id = ?""",
            (title, transcript, transcript_ta, json.dumps(highlights),
             area_name, department, dup_id, " · ".join(problems), issue_id),
        )
        conn.commit()

        row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
        try:
            audit.record(
                conn, issue_id, action="report", actor_type="citizen", actor_id=user_id,
                to_status="SUBMITTED", note=title, department=department,
                image_url=row["image_url"], audio_url=row["audio_url"],
            )
        except Exception:
            pass
        # Notify coordinators once routing + title are known. A suspected
        # duplicate still notifies, and deliberately so: the ward coordinator is
        # one of the two people who can rule on it, and their queue is where
        # they will see the flag.
        try:
            from routers.notifications import emit_new_grievance
            emit_new_grievance(conn, row)
        except Exception:
            pass
        # The reporter is told nothing about a suspected duplicate. Detection is
        # a guess, they cannot act on it, and being told "already reported" on a
        # guess reads as a brush-off. They hear from us only once staff have
        # actually merged it — see duplicates.merge().
        conn.commit()


@router.post("/report")
async def report_issue(
    background: BackgroundTasks,
    latitude: float = Form(...),
    longitude: float = Form(...),
    user_id: str = Form(""),
    title: str = Form("Street Issue"),
    image: UploadFile = File(None),
    audio: UploadFile = File(None),
    # Optional written petition (PDF / doc / scan). The photo and voice note
    # remain the required pair; this is for citizens who arrive with paperwork.
    document: UploadFile = File(None),
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Save the report instantly; transcribe, route and de-duplicate in the
    background.

    The slow work used to run inline, so a submit could take many seconds and
    time out — and a retry then created a second copy of a report that had in
    fact been saved. Now the row is written and returned immediately; the
    background task fills in the AI fields and, if it finds a likely duplicate,
    flags the row so the citizen's own list can offer "submit anyway" or
    "withdraw".
    """
    require_same_citizen(session_uid, user_id)
    user_id = session_uid

    # Refuse out-of-area reports up front — cheap and in-memory. The app blocks
    # the "+" outside GCC too; this is the safety net. No ward means no queue.
    loc = boundaries.locate(latitude, longitude)
    ward_no = int(loc["ward"]) if loc["ward"] is not None else None
    if ward_no is None:
        raise HTTPException(status_code=422, detail=OUTSIDE_GCC_MESSAGE)

    # Persist uploads now so the files exist when the app and the task read them.
    image_url = save_upload(await image.read(), image.filename, "image") if image is not None else None
    audio_bytes = await audio.read() if audio is not None else None
    audio_mime = (audio.content_type or "audio/webm") if audio is not None else "audio/webm"
    audio_url = save_upload(audio_bytes, audio.filename, "audio") if audio_bytes else None
    document_url = None
    document_name = ""
    if document is not None:
        doc_bytes = await document.read()
        if doc_bytes:
            document_name = document.filename or "petition"
            document_url = save_upload(doc_bytes, document_name, "document")

    user_provided_title = bool(
        title and title.strip() and title.strip() != _DEFAULT_TITLE_SENTINEL
    )
    initial_title = title.strip() if user_provided_title else _DEFAULT_TITLE_SENTINEL

    issue_id = new_id()
    created_at = now_iso()
    conn.execute(
        """
        INSERT INTO issues (
            id, title, image_url, audio_url, transcript, transcript_ta,
            summary_highlights, latitude, longitude, area_name, ward_no, zone,
            zone_name, department, ticket_number, document_url, document_name,
            status, upvotes, notify_reporter, processing, created_at, created_by
        ) VALUES (?, ?, ?, ?, '', '', '[]', ?, ?, '', ?, ?, ?, '', ?, ?, ?,
                  'SUBMITTED', 0, 0, 1, ?, ?)
        """,
        (
            issue_id, initial_title, image_url, audio_url, latitude, longitude,
            ward_no, loc["zone"], loc["zone_name"], ticket_number(issue_id),
            document_url, document_name, created_at, user_id,
        ),
    )
    conn.commit()

    # Everything slow runs after this response is sent.
    background.add_task(
        _finish_report, issue_id=issue_id, audio_bytes=audio_bytes,
        audio_mime=audio_mime, latitude=latitude, longitude=longitude,
        user_id=user_id, keep_title=user_provided_title,
    )

    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    result = serialize_issue(row)
    return result


# Duplicate handling used to live here as "/keep" (submit anyway) and
# "/withdraw". Both are gone. /keep erased possible_duplicate_id, so no
# coordinator or admin ever saw the duplicate it was meant to resolve, and
# /withdraw hard-deleted a grievance — photo, voice note and notifications —
# on one tap with no undo. Judging a duplicate is now staff work
# (duplicates.py), and nothing leaves the accountability record.


@router.post("/{issue_id}/upvote")
def upvote_issue(
    issue_id: str,
    user_id: str = Form(""),
    name: str = Form(""),
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Increment upvotes, rejecting a second vote from the same user.

    Public upvotes on someone else's grievance are OTP-verified on the client;
    the verified ``name`` is recorded against the vote.
    """
    require_same_citizen(session_uid, user_id)
    user_id = session_uid
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")

    already = conn.execute(
        "SELECT 1 FROM upvotes WHERE user_id = ? AND issue_id = ?",
        (user_id, issue_id),
    ).fetchone()
    if already:
        raise HTTPException(status_code=409, detail="You have already upvoted this issue")

    conn.execute(
        "INSERT INTO upvotes (id, user_id, issue_id, name) VALUES (?, ?, ?, ?)",
        (new_id(), user_id, issue_id, name),
    )
    conn.execute(
        "UPDATE issues SET upvotes = upvotes + 1 WHERE id = ?", (issue_id,)
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    # A citizen can upvote anyone's grievance, so the echo is the public shape.
    return public_issue(row)


@router.get("/nearby")
def nearby_issues(
    lat: float, lng: float, radius: float = 500.0, conn=Depends(get_db)
):
    """Return every admin-verified issue within ``radius`` meters of (lat, lng).

    SUBMITTED issues are awaiting authority verification and are intentionally
    hidden from the public map until an admin approves them.
    """
    rows = conn.execute(
        "SELECT * FROM issues WHERE status != 'SUBMITTED'"
    ).fetchall()
    results = []
    for row in rows:
        dist = haversine_m(lat, lng, row["latitude"], row["longitude"])
        if dist <= radius:
            item = public_issue(row)
            item["distance_m"] = round(dist, 1)
            results.append(item)
    results.sort(key=lambda x: x["distance_m"])
    return {"count": len(results), "issues": results}


@router.get("/ward/{ward_no}")
def ward_issues(ward_no: int, conn=Depends(get_db)):
    """Public (admin-verified) grievances in a given ward — what citizens see
    for "issues in my ward". SUBMITTED items remain hidden until verified."""
    rows = conn.execute(
        """SELECT * FROM issues
           WHERE ward_no = ? AND status != 'SUBMITTED'
           ORDER BY upvotes DESC, created_at DESC""",
        (ward_no,),
    ).fetchall()
    return {"count": len(rows), "issues": [public_issue(r) for r in rows]}


@router.get("/history/{user_id}")
def user_history(user_id: str,
                 session_uid: str = Depends(citizen_session),
                 conn=Depends(get_db)):
    """Return all issues submitted by ``user_id`` (newest first).

    A report that staff merged into an earlier one is shown as THE EARLIER ONE.
    The reporter follows a single live ticket from then on — the surviving
    grievance, with everyone's support on it and every coordinator update
    flowing to it — instead of a dead-ended row of their own. Their original
    ticket number travels along as ``merged_from_ticket`` so the app can say
    which of their reports this replaced.
    """
    require_same_citizen(session_uid, user_id)
    rows = conn.execute(
        "SELECT * FROM issues WHERE created_by = ? ORDER BY created_at DESC",
        (user_id,),
    ).fetchall()

    out, seen = [], set()
    for row in rows:
        parent_id = row["merged_into_id"]
        if parent_id:
            parent = conn.execute(
                "SELECT * FROM issues WHERE id = ?", (parent_id,)
            ).fetchone()
            if parent is not None:
                # Their own report already stands in for this parent (they
                # reported it twice, or two of their reports were merged into
                # the same one) — don't show the same ticket twice.
                if parent["id"] in seen:
                    continue
                seen.add(parent["id"])
                data = serialize_issue(parent)
                data["merged_from_ticket"] = row["ticket_number"] or ""
                data["merged_at"] = row["merged_at"]
                out.append(data)
                continue
        if row["id"] in seen:
            continue
        seen.add(row["id"])
        out.append(serialize_issue(row))
    return {"count": len(out), "issues": out}


@router.get("/supported/{user_id}")
def user_supported(user_id: str,
                   session_uid: str = Depends(citizen_session),
                   conn=Depends(get_db)):
    """Return the public grievances ``user_id`` has upvoted — the citizen app's
    "My Supports" filter inside the ward feed. SUBMITTED items stay hidden for
    the same reason they are hidden everywhere else: not yet admin-verified.

    ``sort`` mirrors the ward feed: 'recent' (default) or 'priority'.
    """
    require_same_citizen(session_uid, user_id)
    rows = conn.execute(
        """SELECT i.* FROM issues i
           JOIN upvotes u ON u.issue_id = i.id
           WHERE u.user_id = ? AND i.status != 'SUBMITTED'
           ORDER BY i.created_at DESC""",
        (user_id,),
    ).fetchall()
    return {"count": len(rows), "issues": [public_issue(r) for r in rows]}


@router.get("/stats/{user_id}")
def user_stats(user_id: str,
               session_uid: str = Depends(citizen_session),
               conn=Depends(get_db)):
    """Real per-account profile counters shown on the citizen profile:
       reports  — grievances this user submitted
       upvotes  — upvotes this user has cast (their own actions)
       resolved — their submitted grievances now CLOSED
       open     — their submitted grievances not yet assigned to any
                  coordinator (and not terminal)
    """
    require_same_citizen(session_uid, user_id)
    reports = conn.execute(
        "SELECT COUNT(*) AS n FROM issues WHERE created_by = ?", (user_id,)
    ).fetchone()["n"]
    resolved = conn.execute(
        "SELECT COUNT(*) AS n FROM issues WHERE created_by = ? AND status = 'CLOSED'",
        (user_id,),
    ).fetchone()["n"]
    open_count = conn.execute(
        """SELECT COUNT(*) AS n FROM issues
           WHERE created_by = ?
             AND (assigned_coordinator IS NULL OR assigned_coordinator = '')
             AND status NOT IN ('CLOSED', 'FALSE')""",
        (user_id,),
    ).fetchone()["n"]
    upvotes = conn.execute(
        "SELECT COUNT(*) AS n FROM upvotes WHERE user_id = ?", (user_id,)
    ).fetchone()["n"]
    return {
        "reports": reports,
        "upvotes": upvotes,
        "resolved": resolved,
        "open": open_count,
    }


@router.post("/{issue_id}/confirm")
def confirm_issue(
    issue_id: str,
    phone: str = Form(...),
    name: str = Form(""),
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Save the citizen's phone number (and optional name) after OTP verification."""
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    # Only the reporter may attach contact details to their own grievance.
    if (issue["created_by"] or "") != session_uid:
        raise HTTPException(status_code=403, detail="That grievance belongs to another account.")
    if name.strip():
        conn.execute(
            "UPDATE issues SET phone = ?, name = ? WHERE id = ?",
            (phone, name.strip(), issue_id),
        )
    else:
        conn.execute("UPDATE issues SET phone = ? WHERE id = ?", (phone, issue_id))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)


@router.post("/{issue_id}/verify")
def verify_issue(
    issue_id: str,
    user_id: str = Form(""),
    response: str = Form(...),  # APPROVED | REJECTED
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """
    Citizen verification of an admin-resolved issue.
      * APPROVED -> status becomes CLOSED.
      * REJECTED -> status rolls back to IN_PROGRESS (reappears on admin board).
    """
    require_same_citizen(session_uid, user_id)
    user_id = session_uid
    response = response.upper().strip()
    if response not in ("APPROVED", "REJECTED"):
        raise HTTPException(status_code=400, detail="response must be APPROVED or REJECTED")

    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    # Only the person who reported it may accept or reject the resolution.
    # Without this, anyone who knew the grievance id could sign off work on
    # someone else's complaint — including a supporter, who is shown the
    # grievance in their feed and has every id they need. The reporter is the
    # one the coordinator's closure is addressed to, and the one whose
    # rejection sends it back.
    if (issue["created_by"] or "") != user_id:
        raise HTTPException(
            status_code=403,
            detail="Only the citizen who reported this grievance can verify it.",
        )
    if issue["status"] != "PENDING_VERIFICATION":
        raise HTTPException(
            status_code=409,
            detail=f"Issue is not pending verification (status={issue['status']})",
        )

    if response == "APPROVED":
        # resolved_at is what "how long did this take?" is measured against —
        # created_at alone cannot answer it, and CLOSED carried no timestamp.
        conn.execute(
            "UPDATE issues SET status = 'CLOSED', notify_reporter = 0, "
            "resolved_at = ? WHERE id = ?",
            (now_iso(), issue_id),
        )
    else:
        # REJECTED — roll back to ACTIVE (the coordinator's "Assigned" bucket),
        # stamp rejected_at, and clear escalated_at so it lands in the
        # coordinator's Assigned tab (not Escalated). The coordinator app
        # renders an alert card off rejected_at.
        conn.execute(
            """UPDATE issues
                  SET status = 'ACTIVE', notify_reporter = 0,
                      rejected_at = ?, escalated_at = NULL,
                      coordinator_message = 'Citizen rejected the resolution — please review.'
                WHERE id = ?""",
            (now_iso(), issue_id),
        )
    conn.execute(
        """INSERT INTO verifications (id, issue_id, user_id, response, timestamp)
           VALUES (?, ?, ?, ?, ?)""",
        (new_id(), issue_id, user_id, response, now_iso()),
    )
    audit.record(
        conn, issue_id,
        action="citizen_approve" if response == "APPROVED" else "citizen_reject",
        actor_type="citizen", actor_id=user_id,
        from_status="PENDING_VERIFICATION",
        to_status="CLOSED" if response == "APPROVED" else "ACTIVE",
        note=("Citizen confirmed the resolution."
              if response == "APPROVED"
              else "Citizen rejected the resolution."),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    # Tell the owning coordinator either way. Rejection was already covered;
    # approval was not, so a coordinator's screen sat on "Pending verification"
    # after the citizen had already signed the work off — the status only
    # caught up if they force-quit the app.
    try:
        from routers.notifications import emit_to_coordinator
        emit_to_coordinator(
            conn, row,
            "resolved" if response == "APPROVED" else "rejected",
            "Citizen approved the resolution — grievance closed."
            if response == "APPROVED"
            else "Citizen rejected the resolution — review ASAP.",
        )
    except Exception:
        pass  # notifications are best-effort; never fail the verification
    return serialize_issue(row)
