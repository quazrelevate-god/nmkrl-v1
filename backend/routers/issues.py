"""
routers/issues.py
-----------------
Citizen-facing endpoints:
  * POST /api/issues/report         - report (with 50m duplicate check + Gemini)
  * POST /api/issues/{id}/upvote    - upvote (one per user)
  * GET  /api/issues/nearby         - issues within a radius (map view)
  * GET  /api/issues/history/{uid}  - a user's submissions
  * POST /api/issues/{id}/verify    - citizen approves/rejects a resolution
"""

import json

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

import audit
import boundaries
from database import get_db
from gemini_service import check_duplicate, classify_department, process_audio
from utils import (
    haversine_m,
    new_id,
    now_iso,
    reverse_geocode,
    save_upload,
    serialize_issue,
    ticket_number,
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


@router.post("/report")
async def report_issue(
    latitude: float = Form(...),
    longitude: float = Form(...),
    user_id: str = Form(...),
    title: str = Form("Street Issue"),
    force: bool = Form(False),
    image: UploadFile = File(None),
    audio: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Report a new street issue. Transcribe audio via Gemini, then check for
    semantic duplicates among nearby open issues before persisting."""
    # --- Reject out-of-area reports FIRST ------------------------------------
    # A point outside every GCC ward polygon has no ward, and BOTH the public
    # ward feed and every coordinator queue filter on ward_no — so such a row
    # would be invisible to everyone but its reporter, with no coordinator
    # notified and nothing to route it. Refusing here (rather than after the
    # write) also avoids paying for a Gemini transcription and leaving orphaned
    # upload files behind for a grievance that can never be acted on.
    loc = boundaries.locate(latitude, longitude)
    ward_no = int(loc["ward"]) if loc["ward"] is not None else None
    zone = loc["zone"]
    zone_name = loc["zone_name"]
    if ward_no is None:
        raise HTTPException(status_code=422, detail=OUTSIDE_GCC_MESSAGE)

    # --- Persist uploaded media ---------------------------------------------
    image_url = None
    audio_url = None
    audio_bytes = None
    audio_mime = "audio/webm"

    if image is not None:
        image_url = save_upload(await image.read(), image.filename, "image")
    if audio is not None:
        audio_bytes = await audio.read()
        audio_mime = audio.content_type or "audio/webm"
        audio_url = save_upload(audio_bytes, audio.filename, "audio")

    # --- Gemini transcription -----------------------------------------------
    if audio_bytes:
        ai = process_audio(audio_bytes, mime_type=audio_mime)
    else:
        ai = {"title": "", "transcript": "", "highlights": []}

    # --- Title resolution ---------------------------------------------------
    # Prefer a user-typed title; otherwise use Gemini's summarised title; last
    # resort, keep the sentinel so the issue still has something.
    user_provided_title = title and title.strip() != _DEFAULT_TITLE_SENTINEL
    gemini_title = (ai.get("title") or "").strip()
    if not user_provided_title and gemini_title:
        title = gemini_title

    # --- Gemini-powered duplicate check within 100m (skip if force=true) ---
    # Similarity is decided by Gemini over the summary/transcript/highlights;
    # proximity is only the initial filter.
    if not force:
        nearby = _nearby_open_issues(conn, latitude, longitude, DUPLICATE_RADIUS_M)
        if nearby:
            dup = check_duplicate(
                title,
                ai.get("transcript", ""),
                ai.get("highlights", []),
                nearby,
            )
            if dup is not None:
                payload = serialize_issue(
                    conn.execute("SELECT * FROM issues WHERE id = ?", (dup["id"],)).fetchone()
                )
                payload["distance_m"] = dup.get("distance_m", 0)
                return {"duplicate_exists": True, "existing_issue": payload}

    # --- Persist the new issue ----------------------------------------------
    area_name = reverse_geocode(latitude, longitude)
    department = classify_department(
        title, ai.get("transcript", ""), ai.get("highlights", [])
    )

    issue_id = new_id()
    created_at = now_iso()
    conn.execute(
        """
        INSERT INTO issues (
            id, title, image_url, audio_url, transcript, transcript_ta,
            summary_highlights, latitude, longitude, area_name, ward_no, zone,
            zone_name, department, ticket_number,
            status, upvotes, notify_reporter, created_at, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'SUBMITTED', 0, 0, ?, ?)
        """,
        (
            issue_id,
            title,
            image_url,
            audio_url,
            ai.get("transcript", ""),
            ai.get("transcript_ta", ""),
            json.dumps(ai.get("highlights", [])),
            latitude,
            longitude,
            area_name,
            ward_no,
            zone,
            zone_name,
            department,
            ticket_number(issue_id),
            created_at,
            user_id,
        ),
    )

    audit.record(
        conn, issue_id, action="report", actor_type="citizen", actor_id=user_id,
        to_status="SUBMITTED", note=title, department=department,
        image_url=image_url, audio_url=audio_url,
    )

    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    # Push a floating banner to every coordinator whose home_ward matches
    # this grievance — the mobile coordinator app polls /api/notifications
    # every ~15s and pops a banner for each new entry.
    try:
        from routers.notifications import emit_new_grievance
        emit_new_grievance(conn, row)
    except Exception:
        pass  # notifications are best-effort; never block the report
    result = serialize_issue(row)
    result["duplicate_exists"] = False
    result["ai_meta"] = {"mock": ai.get("mock", False), "reason": ai.get("reason")}
    return result


@router.post("/{issue_id}/upvote")
def upvote_issue(
    issue_id: str,
    user_id: str = Form(...),
    name: str = Form(""),
    conn=Depends(get_db),
):
    """Increment upvotes, rejecting a second vote from the same user.

    Public upvotes on someone else's grievance are OTP-verified on the client;
    the verified ``name`` is recorded against the vote.
    """
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
    return serialize_issue(row)


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
            item = serialize_issue(row)
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
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/history/{user_id}")
def user_history(user_id: str, conn=Depends(get_db)):
    """Return all issues submitted by ``user_id`` (newest first)."""
    rows = conn.execute(
        "SELECT * FROM issues WHERE created_by = ? ORDER BY created_at DESC",
        (user_id,),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/supported/{user_id}")
def user_supported(user_id: str, conn=Depends(get_db)):
    """Return the public grievances ``user_id`` has upvoted — the citizen app's
    "My Supports" filter inside the ward feed. SUBMITTED items stay hidden for
    the same reason they are hidden everywhere else: not yet admin-verified.

    ``sort`` mirrors the ward feed: 'recent' (default) or 'priority'.
    """
    rows = conn.execute(
        """SELECT i.* FROM issues i
           JOIN upvotes u ON u.issue_id = i.id
           WHERE u.user_id = ? AND i.status != 'SUBMITTED'
           ORDER BY i.created_at DESC""",
        (user_id,),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.get("/stats/{user_id}")
def user_stats(user_id: str, conn=Depends(get_db)):
    """Real per-account profile counters shown on the citizen profile:
       reports  — grievances this user submitted
       upvotes  — upvotes this user has cast (their own actions)
       resolved — their submitted grievances now CLOSED
       open     — their submitted grievances not yet assigned to any
                  coordinator (and not terminal)
    """
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
    conn=Depends(get_db),
):
    """Save the citizen's phone number (and optional name) after OTP verification."""
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
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
    user_id: str = Form(...),
    response: str = Form(...),  # APPROVED | REJECTED
    conn=Depends(get_db),
):
    """
    Citizen verification of an admin-resolved issue.
      * APPROVED -> status becomes CLOSED.
      * REJECTED -> status rolls back to IN_PROGRESS (reappears on admin board).
    """
    response = response.upper().strip()
    if response not in ("APPROVED", "REJECTED"):
        raise HTTPException(status_code=400, detail="response must be APPROVED or REJECTED")

    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
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
    # Notify the owning coordinator that the citizen rejected the closure.
    if response == "REJECTED" and row["assigned_coordinator"]:
        try:
            from routers.notifications import _insert
            _insert(
                conn,
                recipient_type="coordinator",
                recipient_id=row["assigned_coordinator"],
                kind="rejected",
                issue_id=issue_id,
                title=row["title"] or "Grievance rejected",
                message="Citizen rejected the resolution — review ASAP.",
                data={"ward_no": row["ward_no"]},
            )
        except Exception:
            pass
    return serialize_issue(row)
