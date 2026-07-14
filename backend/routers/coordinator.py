"""
routers/coordinator.py
----------------------
Coordinator-facing endpoints. Each of the four action buttons on the
coordinator's My Reports view calls one of these — the endpoint updates the
backend status of the grievance so the citizen app immediately reflects the
new state.

  POST /api/coordinator/issues/{id}/verify    → SUBMITTED / any → ACTIVE
                                                (coordinator takes ownership;
                                                citizen sees "Assigned")
  POST /api/coordinator/issues/{id}/transfer  → ACTIVE/FORWARDED → FORWARDED
                                                (labeled "Inspection" in the
                                                citizen app), routed to a
                                                chosen department
  POST /api/coordinator/issues/{id}/redirect  → any → SUBMITTED with a
                                                delay-apology message shown
                                                to the citizen
  POST /api/coordinator/issues/{id}/close     → open → PENDING_VERIFICATION
                                                (citizen sees the verify prompt)
  POST /api/coordinator/issues/{id}/mark_false→ any → FALSE with a stored
                                                reason (citizen sees
                                                "Marked as false petition")

Also a coordinator-only ward listing endpoint that returns EVERY status
(including SUBMITTED) so coordinators can verify pending grievances — the
public /api/issues/ward/{n} intentionally hides SUBMITTED from citizens.
"""

from fastapi import APIRouter, Depends, Form, HTTPException

from database import get_db
from utils import serialize_issue

router = APIRouter(prefix="/api/coordinator", tags=["coordinator"])


def _load(conn, issue_id):
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    return row


@router.get("/ward/{ward_no}")
def coordinator_ward_issues(ward_no: int, conn=Depends(get_db)):
    """Every grievance in the ward, regardless of status — for coordinator use."""
    rows = conn.execute(
        "SELECT * FROM issues WHERE ward_no = ? ORDER BY created_at DESC",
        (ward_no,),
    ).fetchall()
    return {"count": len(rows), "issues": [serialize_issue(r) for r in rows]}


@router.post("/issues/{issue_id}/verify")
def coord_verify(issue_id: str, conn=Depends(get_db)):
    """Coordinator takes ownership: any → ACTIVE. Citizen sees 'Assigned'."""
    _load(conn, issue_id)
    conn.execute(
        "UPDATE issues SET status = 'ACTIVE', coordinator_message = '' WHERE id = ?",
        (issue_id,),
    )
    row = _load(conn, issue_id)
    return serialize_issue(row)


@router.post("/issues/{issue_id}/transfer")
def coord_transfer(
    issue_id: str,
    department: str = Form(...),
    notes: str = Form(""),
    conn=Depends(get_db),
):
    """Dept. Transfer: → FORWARDED (labeled 'Inspection' in citizen app)."""
    _load(conn, issue_id)
    msg = f"Routed to {department} for inspection." + (f" Note: {notes}" if notes else "")
    conn.execute(
        "UPDATE issues SET status = 'FORWARDED', department = ?, coordinator_message = ? WHERE id = ?",
        (department, msg, issue_id),
    )
    row = _load(conn, issue_id)
    return serialize_issue(row)


@router.post("/issues/{issue_id}/redirect")
def coord_redirect(
    issue_id: str,
    description: str = Form(...),
    conn=Depends(get_db),
):
    """Redirect: → SUBMITTED with a delay-apology message shown to the citizen."""
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
    return serialize_issue(row)


@router.post("/issues/{issue_id}/mark_false")
def coord_mark_false(
    issue_id: str,
    reason: str = Form(...),
    details: str = Form(""),
    conn=Depends(get_db),
):
    """Mark false: → FALSE with the coordinator's reason."""
    _load(conn, issue_id)
    msg = f"Marked as false petition. Reason: {reason}" + (f" — {details}" if details else "")
    conn.execute(
        "UPDATE issues SET status = 'FALSE', coordinator_message = ? WHERE id = ?",
        (msg, issue_id),
    )
    row = _load(conn, issue_id)
    return serialize_issue(row)
