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
)

router = APIRouter(prefix="/api/issues", tags=["issues"])

DUPLICATE_RADIUS_M = 200.0


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
        ai = {"transcript": "", "highlights": []}

    # --- Gemini-powered duplicate check (skip if force=true) ----------------
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
    # Real GCC zone + ward via point-in-polygon over the KML boundaries.
    loc = boundaries.locate(latitude, longitude)
    ward_no = int(loc["ward"]) if loc["ward"] is not None else None
    zone = loc["zone"]
    zone_name = loc["zone_name"]
    department = classify_department(
        title, ai.get("transcript", ""), ai.get("highlights", [])
    )

    issue_id = new_id()
    created_at = now_iso()
    conn.execute(
        """
        INSERT INTO issues (
            id, title, image_url, audio_url, transcript, summary_highlights,
            latitude, longitude, area_name, ward_no, zone, zone_name, department,
            status, upvotes, notify_reporter, created_at, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'SUBMITTED', 0, 0, ?, ?)
        """,
        (
            issue_id,
            title,
            image_url,
            audio_url,
            ai.get("transcript", ""),
            json.dumps(ai.get("highlights", [])),
            latitude,
            longitude,
            area_name,
            ward_no,
            zone,
            zone_name,
            department,
            created_at,
            user_id,
        ),
    )

    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
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

    new_status = "CLOSED" if response == "APPROVED" else "IN_PROGRESS"
    conn.execute(
        "UPDATE issues SET status = ?, notify_reporter = 0 WHERE id = ?",
        (new_status, issue_id),
    )
    conn.execute(
        """INSERT INTO verifications (id, issue_id, user_id, response, timestamp)
           VALUES (?, ?, ?, ?, ?)""",
        (new_id(), issue_id, user_id, response, now_iso()),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)
