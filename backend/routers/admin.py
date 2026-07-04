"""
routers/admin.py
----------------
Authority/triage endpoints:
  * GET  /api/admin/issues               - filterable queue (all statuses)
  * POST /api/admin/issues/{id}/verify   - SUBMITTED -> ACTIVE (approve grievance)
  * POST /api/admin/issues/{id}/close    - mark resolved -> PENDING_VERIFICATION
  * POST /api/admin/issues/{id}/progress - ACTIVE -> IN_PROGRESS
"""

from fastapi import APIRouter, Depends, HTTPException, Query

from database import get_db
from utils import serialize_issue

router = APIRouter(prefix="/api/admin", tags=["admin"])

VALID_STATUSES = {
    "SUBMITTED", "ACTIVE", "FORWARDED", "IN_PROGRESS",
    "PENDING_VERIFICATION", "CLOSED",
}


@router.get("/issues")
def list_admin_issues(
    status: str = Query(None),
    sort: str = Query("upvotes"),
    zone: str = Query(None),
    ward: int = Query(None),
    conn=Depends(get_db),
):
    """
    Return issues with optional filtering.
    - status: SUBMITTED, ACTIVE, IN_PROGRESS, PENDING_VERIFICATION, CLOSED,
      or omit for ALL issues (the dashboard/heatmap needs the full set).
    - zone: filter to a single GCC zone (roman numeral, e.g. "VIII").
    - ward: filter to a single ward number.
    - sort: 'upvotes' (default) or 'recent'
    """
    clauses, params = [], []
    if status and status.upper() in VALID_STATUSES:
        clauses.append("status = ?")
        params.append(status.upper())
    if zone:
        clauses.append("zone = ?")
        params.append(zone)
    if ward is not None:
        clauses.append("ward_no = ?")
        params.append(ward)

    sql = "SELECT * FROM issues"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    rows = conn.execute(sql, params).fetchall()

    issues = [serialize_issue(r) for r in rows]

    if sort == "recent":
        issues.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    else:
        issues.sort(key=lambda x: (-x.get("upvotes", 0), x.get("created_at", "")))

    return {"count": len(issues), "issues": issues}


@router.post("/issues/{issue_id}/verify")
def verify_grievance(issue_id: str, conn=Depends(get_db)):
    """Authority approves a freshly submitted grievance: SUBMITTED -> ACTIVE.

    This is the gate that makes the issue public — only now does its pin
    appear on the citizen map and the status tracker advance to 'Assigned'.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] != "SUBMITTED":
        raise HTTPException(
            status_code=409,
            detail=f"Only SUBMITTED grievances can be verified (status={issue['status']})",
        )
    conn.execute("UPDATE issues SET status = 'ACTIVE' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)


@router.post("/issues/{issue_id}/forward")
def forward_issue(issue_id: str, conn=Depends(get_db)):
    """Forward a verified grievance to its routed department: ACTIVE -> FORWARDED.

    This is the hand-off step (the WhatsApp/department dispatch) — it marks the
    ticket as forwarded so it shows under the 'Forwarded' queue.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "IN_PROGRESS"):
        raise HTTPException(
            status_code=409,
            detail=f"Only open tickets can be forwarded (status={issue['status']})",
        )
    conn.execute("UPDATE issues SET status = 'FORWARDED' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
def close_issue(issue_id: str, conn=Depends(get_db)):
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "FORWARDED", "IN_PROGRESS"):
        raise HTTPException(
            status_code=409,
            detail=f"Only open issues can be resolved (status={issue['status']})",
        )
    conn.execute(
        "UPDATE issues SET status = 'PENDING_VERIFICATION', notify_reporter = 1 WHERE id = ?",
        (issue_id,),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    result = serialize_issue(row)
    result["notification_sent_to"] = issue["created_by"]
    return result


@router.post("/issues/{issue_id}/progress")
def mark_in_progress(issue_id: str, conn=Depends(get_db)):
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "FORWARDED"):
        raise HTTPException(
            status_code=409,
            detail=f"Only ACTIVE/FORWARDED issues can move to IN_PROGRESS (status={issue['status']})",
        )
    conn.execute("UPDATE issues SET status = 'IN_PROGRESS' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)
