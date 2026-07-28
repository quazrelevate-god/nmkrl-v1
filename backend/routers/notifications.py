"""
routers/notifications.py
------------------------
Lightweight polling push queue. The mobile apps poll `/api/notifications`
every ~15 seconds while foregrounded and pop a floating banner for each new
entry.

  citizens get:  status_change (their reported grievance moved forward)
  coordinators get:  new_grievance (a citizen submitted in their ward)

Server-side, the issues router calls `emit_status_change()` and
`emit_new_grievance()` at the appropriate transitions (see routers/issues.py
and routers/coordinator.py).
"""

import json

from fastapi import APIRouter, Depends

from database import get_db
from utils import new_id, now_iso

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


def _insert(conn, *, recipient_type: str, recipient_id: str,
            kind: str, issue_id: str, title: str = "",
            message: str = "", data: dict | None = None) -> None:
    if not recipient_id:
        return
    conn.execute(
        """INSERT INTO notifications
           (id, recipient_type, recipient_id, kind, issue_id, title, message,
            data, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            new_id(), recipient_type, str(recipient_id), kind, issue_id,
            title or "", message or "",
            json.dumps(data or {}),
            now_iso(),
        ),
    )


def emit_status_change(conn, issue_row, kind: str, message: str) -> None:
    """Notify the citizen who reported the grievance."""
    recipient = issue_row["created_by"] if issue_row else None
    _insert(
        conn,
        recipient_type="citizen",
        recipient_id=str(recipient or ""),
        kind=kind,
        issue_id=issue_row["id"],
        title=issue_row["title"] or "Your grievance",
        message=message,
        data={"status": issue_row["status"], "ward_no": issue_row["ward_no"]},
    )


def emit_new_grievance(conn, issue_row) -> None:
    """Notify every coordinator whose home_ward matches the new grievance."""
    ward_no = issue_row["ward_no"]
    if ward_no is None:
        return
    constituency = None
    # Loop coordinators mapped to this ward (by home_ward) — this is the
    # deliberate coarse filter for phase-1 (each coordinator owns one ward).
    coords = conn.execute(
        "SELECT username, constituency FROM coordinators WHERE home_ward = ?",
        (str(ward_no),),
    ).fetchall()
    for c in coords:
        _insert(
            conn,
            recipient_type="coordinator",
            recipient_id=c["username"],
            kind="new_grievance",
            issue_id=issue_row["id"],
            title=issue_row["title"] or "New grievance",
            message=f"New grievance in Ward {ward_no}",
            data={
                "ward_no": ward_no,
                "constituency": c["constituency"],
                "latitude": issue_row["latitude"],
                "longitude": issue_row["longitude"],
            },
        )
        constituency = c["constituency"]
    _ = constituency  # silence unused


@router.get("")
def list_notifications(
    recipient_type: str,
    recipient_id: str,
    since: str = "",
    limit: int = 20,
    conn=Depends(get_db),
):
    """
    Return unseen notifications for a recipient. `since` is an ISO timestamp
    (the client's last-seen marker); results are strictly newer than that.
    """
    limit = max(1, min(limit, 100))
    if since:
        rows = conn.execute(
            """SELECT * FROM notifications
               WHERE recipient_type = ? AND recipient_id = ?
                 AND created_at > ?
               ORDER BY created_at DESC LIMIT ?""",
            (recipient_type, recipient_id, since, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            """SELECT * FROM notifications
               WHERE recipient_type = ? AND recipient_id = ?
               ORDER BY created_at DESC LIMIT ?""",
            (recipient_type, recipient_id, limit),
        ).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        try:
            d["data"] = json.loads(d.get("data") or "{}")
        except (TypeError, ValueError):
            d["data"] = {}
        out.append(d)
    return {"count": len(out), "notifications": out, "server_time": now_iso()}
