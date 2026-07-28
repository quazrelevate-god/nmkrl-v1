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

  GET  /api/coordinator/ward/{n}
       ?coordinator=<username>       required — filters ownership properly
       ?sort=recent|priority         optional — created_at desc / upvotes desc
    Returns:
       • unassigned open grievances (any coordinator may verify)
       • grievances assigned TO <coordinator> (in every state)
       • hides grievances assigned to a DIFFERENT coordinator
"""

from fastapi import APIRouter, Depends, Form, HTTPException, Query

from database import get_db
from utils import now_iso, serialize_issue
from routers.notifications import emit_status_change

router = APIRouter(prefix="/api/coordinator", tags=["coordinator"])


def _load(conn, issue_id):
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    return row


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
    if (prev["assigned_coordinator"] or "").strip() not in ("", coordinator.strip().lower()):
        raise HTTPException(
            status_code=409,
            detail=f"Already assigned to @{prev['assigned_coordinator']}.",
        )
    conn.execute(
        """UPDATE issues
              SET status = 'ACTIVE', coordinator_message = '',
                  assigned_coordinator = ?
            WHERE id = ?""",
        (coordinator.strip().lower(), issue_id),
    )
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "assigned",
        f"Your grievance has been assigned to a coordinator.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/transfer")
def coord_transfer(
    issue_id: str,
    department: str = Form(...),
    notes: str = Form(""),
    officer: str = Form(""),
    conn=Depends(get_db),
):
    """Dept. Transfer: → FORWARDED with dept + optional responsible officer."""
    _load(conn, issue_id)
    if officer:
        msg = f"Routed to {department} — Responsible officer: {officer}."
    else:
        msg = f"Routed to {department} for inspection."
    if notes:
        msg += f" Note: {notes}"
    conn.execute(
        "UPDATE issues SET status = 'FORWARDED', department = ?, "
        "coordinator_message = ? WHERE id = ?",
        (department, msg, issue_id),
    )
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "transfer",
        f"Your grievance was transferred to {department}.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/escalate")
def coord_escalate(
    issue_id: str,
    description: str = Form(...),
    conn=Depends(get_db),
):
    """Escalate: → IN_PROGRESS + escalated_at now(). Mobile groups these into
    a dedicated 'Escalated' tab and keeps them out of 'My Reports'."""
    _load(conn, issue_id)
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
    conn=Depends(get_db),
):
    """Redirect: → SUBMITTED with a delay-apology message."""
    _load(conn, issue_id)
    msg = (
        "Sorry for the delay, will re-assign another team to resolve this issue faster. "
        f"Reason: {description}"
    )
    conn.execute(
        "UPDATE issues SET status = 'SUBMITTED', coordinator_message = ? WHERE id = ?",
        (msg, issue_id),
    )
    row = _load(conn, issue_id)
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
def coord_close(
    issue_id: str,
    notes: str = Form(""),
    conn=Depends(get_db),
):
    """Close: → PENDING_VERIFICATION (citizen sees the verify/reject prompt)."""
    _load(conn, issue_id)
    conn.execute(
        "UPDATE issues SET status = 'PENDING_VERIFICATION', notify_reporter = 1, "
        "coordinator_message = ? WHERE id = ?",
        (notes or "Coordinator has closed this ticket. Please verify the resolution.", issue_id),
    )
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "closed",
        "Your grievance is marked resolved — please approve or reject to confirm.",
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/mark_false")
def coord_mark_false(
    issue_id: str,
    reason: str = Form(...),
    details: str = Form(""),
    coordinator: str = Form(""),
    conn=Depends(get_db),
):
    """Mark false: → FALSE with the coordinator's reason. Also records
    ownership so it lands in the acting coordinator's Previous tab."""
    _load(conn, issue_id)
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
    row = _load(conn, issue_id)
    emit_status_change(
        conn, row, "false",
        "Your grievance was marked as a false petition.",
    )
    return serialize_issue(row)
