"""
routers/coordinators_admin.py
-----------------------------
Admin-console CRUD for constituency-staff (coordinator) accounts.

The web admin's "Coordinators" page manages this table; the coordinator app's
sign-in authenticates against it. Coordinators sign in with **name + mobile
number + OTP** — there are no passwords. The admin sets a name, a mobile number,
role, constituency and home ward; a `username` is auto-generated and kept only
as an internal, admin-invisible key so a coordinator's already-assigned
grievances, notifications and history stay linked to them.
"""

import re
import secrets

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from database import get_db
from tenancy import current_tenant, owns_ward
from utils import new_id, now_iso, save_upload

router = APIRouter(prefix="/api/admin/coordinators", tags=["admin-coordinators"])


def _normalise_phone(raw: str) -> str:
    """Digits only, last 10 (Indian mobile)."""
    digits = re.sub(r"\D", "", raw or "")
    return digits[-10:] if len(digits) >= 10 else digits


def _serialize(row) -> dict:
    d = dict(row)
    # Password is gone from the flow; never leak it even if a legacy value lingers.
    d.pop("password", None)
    d["must_change_password"] = bool(d.get("must_change_password", 0))
    d["phone"] = d.get("phone") or ""
    return d


def _make_username(conn, name: str) -> str:
    """A stable, opaque internal id derived from the name plus randomness.

    Never shown to the admin or typed by anyone — it exists only so the many
    places that key a coordinator by `username` (assigned grievances,
    notifications, the session token, the audit trail) keep a single identity.
    """
    base = re.sub(r"[^a-z0-9]", "", (name or "").lower())[:16] or "coord"
    for _ in range(20):
        candidate = f"{base}{secrets.token_hex(2)}"
        if conn.execute(
            "SELECT 1 FROM coordinators WHERE username = ?", (candidate,)
        ).fetchone() is None:
            return candidate
    return f"coord{secrets.token_hex(4)}"


def _phone_taken(conn, phone: str, *, exclude_username: str = "") -> bool:
    row = conn.execute(
        "SELECT username FROM coordinators WHERE phone = ? AND phone <> ''",
        (phone,),
    ).fetchone()
    return row is not None and row["username"] != exclude_username


def _own(conn, username: str, tenant: dict):
    """One of this office's coordinators, or 404.

    A coordinator of another constituency answers like one that does not exist.
    """
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ? AND constituency = ?",
        ((username or "").lower(), tenant["constituency"]),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Coordinator not found.")
    return row


def _check_scope(tenant: dict, constituency, home_ward) -> None:
    """A coordinator can only be placed inside this office's constituency."""
    if constituency not in (None, "") and constituency != tenant["constituency"]:
        raise HTTPException(
            status_code=400,
            detail=f"Coordinators here belong to {tenant['constituency']}.",
        )
    if home_ward not in (None, "") and not owns_ward(tenant, home_ward):
        raise HTTPException(
            status_code=400,
            detail=f"Ward {home_ward} is outside {tenant['constituency']}.",
        )


class CoordinatorCreate(BaseModel):
    name: str
    phone: str
    role: str
    # Always the office's own constituency; accepted only so existing clients
    # that still send it keep working, and refused if it names another.
    constituency: str = ""
    home_ward: str


class CoordinatorUpdate(BaseModel):
    name: str | None = None
    role: str | None = None
    constituency: str | None = None
    home_ward: str | None = None
    phone: str | None = None
    status: str | None = None  # 'active' | 'disabled'


@router.get("")
def list_coordinators(tenant: dict = Depends(current_tenant), conn=Depends(get_db)):
    rows = conn.execute(
        "SELECT * FROM coordinators WHERE constituency = ? ORDER BY created_at DESC",
        (tenant["constituency"],),
    ).fetchall()
    return {"count": len(rows), "coordinators": [_serialize(r) for r in rows]}


@router.post("")
def create_coordinator(
    body: CoordinatorCreate, tenant: dict = Depends(current_tenant), conn=Depends(get_db)
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required.")
    _check_scope(tenant, body.constituency, body.home_ward)
    if not (body.home_ward or "").strip():
        raise HTTPException(status_code=400, detail="A home ward is required.")
    phone = _normalise_phone(body.phone)
    if len(phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")
    if _phone_taken(conn, phone):
        raise HTTPException(
            status_code=409,
            detail="Another coordinator already uses that mobile number.",
        )

    coord_id = new_id()
    username = _make_username(conn, name)
    conn.execute(
        """INSERT INTO coordinators
           (id, username, password, name, role, constituency, home_ward, phone,
            must_change_password, status, created_at)
           VALUES (?, ?, '', ?, ?, ?, ?, ?, 0, 'active', ?)""",
        (
            coord_id, username, name, body.role, tenant["constituency"],
            body.home_ward, phone, now_iso(),
        ),
    )
    row = conn.execute("SELECT * FROM coordinators WHERE id = ?", (coord_id,)).fetchone()
    return _serialize(row)


def _release_open_work(conn, username: str, why: str) -> int:
    """Put a coordinator's unfinished grievances back in the ward pool.

    Disabling or deleting an account left its grievances "assigned" to someone
    who could no longer act: hidden from every other coordinator, refused if
    they tried to take them, and missing from the office's Unassigned view.
    Grievances awaiting the citizen's confirmation keep their owner; if the
    citizen rejects the fix, that path re-releases them (routers/issues.py).
    Also forgets the account's phones, so no more pushes reach it.
    """
    import audit
    from routers.notifications import emit_new_grievance

    who = (username or "").strip().lower()
    rows = conn.execute(
        """SELECT * FROM issues WHERE LOWER(assigned_coordinator) = ?
             AND status IN ('SUBMITTED', 'ACTIVE', 'FORWARDED', 'IN_PROGRESS')""",
        (who,),
    ).fetchall()
    for r in rows:
        conn.execute(
            "UPDATE issues SET assigned_coordinator = '', assigned_at = NULL WHERE id = ?",
            (r["id"],),
        )
        audit.record(
            conn, r["id"], action="release", actor_type="admin", actor_id="admin",
            from_status=r["status"], to_status=r["status"],
            note=f"Released from @{who}: {why}.",
        )
        fresh = conn.execute("SELECT * FROM issues WHERE id = ?", (r["id"],)).fetchone()
        try:
            emit_new_grievance(conn, fresh)
        except Exception:
            pass
    conn.execute(
        "DELETE FROM device_tokens WHERE recipient_type = 'coordinator' AND LOWER(recipient_id) = ?",
        (who,),
    )
    return len(rows)


@router.patch("/{username}")
def update_coordinator(
    username: str, body: CoordinatorUpdate, tenant: dict = Depends(current_tenant), conn=Depends(get_db)
):
    before = _own(conn, username, tenant)
    _check_scope(tenant, body.constituency, body.home_ward)

    updates, params = [], []
    for col, val in [
        ("name", body.name.strip() if body.name is not None else None),
        ("role", body.role),
        ("constituency", body.constituency),
        ("home_ward", body.home_ward),
        ("status", body.status.lower() if body.status else None),
    ]:
        if val is not None:
            updates.append(f"{col} = ?")
            params.append(val)

    if body.phone is not None:
        phone = _normalise_phone(body.phone)
        if phone and len(phone) != 10:
            raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")
        if phone and _phone_taken(conn, phone, exclude_username=username.lower()):
            raise HTTPException(
                status_code=409,
                detail="Another coordinator already uses that mobile number.",
            )
        updates.append("phone = ?")
        params.append(phone)

    if updates:
        params.append(username.lower())
        conn.execute(
            f"UPDATE coordinators SET {', '.join(updates)} WHERE username = ?",
            params,
        )
    was_active = (before["status"] or "active").lower() == "active"
    if was_active and body.status and body.status.lower() != "active":
        _release_open_work(conn, username, "account disabled")
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ?", (username.lower(),)
    ).fetchone()
    return _serialize(row)


@router.post("/{username}/photo")
async def set_coordinator_photo(
    username: str,
    photo: UploadFile = File(None),
    tenant: dict = Depends(current_tenant),
    conn=Depends(get_db),
):
    """Upload (or clear) a coordinator's profile photo. Admin uploads it by
    hand — there are no random avatars."""
    _own(conn, username, tenant)
    photo_url = ""
    if photo is not None:
        data = await photo.read()
        if data:
            photo_url = save_upload(data, photo.filename, "image")
    conn.execute(
        "UPDATE coordinators SET photo_url = ? WHERE username = ?",
        (photo_url, username.lower()),
    )
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ?", (username.lower(),)
    ).fetchone()
    return _serialize(row)


@router.delete("/{username}")
def delete_coordinator(
    username: str, tenant: dict = Depends(current_tenant), conn=Depends(get_db)
):
    _own(conn, username, tenant)
    released = _release_open_work(conn, username, "account deleted")
    conn.execute("DELETE FROM coordinators WHERE username = ?", (username.lower(),))
    return {"deleted": username.lower(), "released": released}
