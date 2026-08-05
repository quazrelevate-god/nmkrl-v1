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
import os

from fastapi import APIRouter, Body, Depends

import push
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
    # Second delivery channel: reaches the device when the app is backgrounded
    # or closed, where the 15s poller cannot. No-ops when FCM is unconfigured,
    # and never raises — a failed push must not fail the action behind it.
    push.send_to_recipient(
        conn,
        recipient_type=recipient_type,
        recipient_id=str(recipient_id),
        title=title or "நம்குரல்",
        body=message or "",
        data={**(data or {}), "kind": kind, "issue_id": issue_id},
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


@router.get("/push-status")
def push_status(
    recipient_type: str = "",
    recipient_id: str = "",
    conn=Depends(get_db),
):
    """Diagnostics for the push path — never exposes the credential itself.

    Reports whether FCM is configured on this deploy and how many device
    tokens are registered, so 'no notification arrived' can be narrowed to a
    missing variable vs a device that never registered.
    """
    total = conn.execute("SELECT COUNT(*) c FROM device_tokens").fetchone()["c"]
    mine = None
    if recipient_type and recipient_id:
        mine = conn.execute(
            "SELECT COUNT(*) c FROM device_tokens "
            "WHERE recipient_type = ? AND recipient_id = ?",
            (recipient_type, recipient_id),
        ).fetchone()["c"]
    return {
        "project_id_set": bool(push._project_id()),
        "service_account_set": bool(os.environ.get("FCM_SERVICE_ACCOUNT_JSON")),
        "access_token_ok": push._access_token() is not None,
        "tokens_total": total,
        "tokens_for_recipient": mine,
    }


@router.post("/register")
def register_device(
    payload: dict = Body(...),
    conn=Depends(get_db),
):
    """Store an FCM token against the signed-in account.

    Upsert on the token itself: reinstalling or switching accounts on the same
    device rebinds the row rather than leaving a stale one behind, so a device
    is never registered to two accounts at once.
    """
    token = (payload.get("token") or "").strip()
    recipient_type = (payload.get("recipient_type") or "").strip()
    recipient_id = str(payload.get("recipient_id") or "").strip()
    platform = (payload.get("platform") or "android").strip()
    if not token or not recipient_type or not recipient_id:
        return {"ok": False, "error": "token, recipient_type, recipient_id required"}
    conn.execute(
        """INSERT INTO device_tokens
               (token, recipient_type, recipient_id, platform, updated_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(token) DO UPDATE SET
               recipient_type = excluded.recipient_type,
               recipient_id   = excluded.recipient_id,
               platform       = excluded.platform,
               updated_at     = excluded.updated_at""",
        (token, recipient_type, recipient_id, platform, now_iso()),
    )
    conn.commit()
    return {"ok": True}


@router.post("/unregister")
def unregister_device(payload: dict = Body(...), conn=Depends(get_db)):
    """Drop a token on sign-out.

    Without this a device keeps receiving the previous account's alerts — which
    matters here because one phone switches between the citizen and coordinator
    roles.
    """
    token = (payload.get("token") or "").strip()
    if not token:
        return {"ok": False, "error": "token required"}
    conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))
    conn.commit()
    return {"ok": True}
