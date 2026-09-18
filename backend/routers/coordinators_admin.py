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

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from database import get_db
from utils import new_id, now_iso

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


class CoordinatorCreate(BaseModel):
    name: str
    phone: str
    role: str
    constituency: str
    home_ward: str


class CoordinatorUpdate(BaseModel):
    name: str | None = None
    role: str | None = None
    constituency: str | None = None
    home_ward: str | None = None
    phone: str | None = None
    status: str | None = None  # 'active' | 'disabled'


@router.get("")
def list_coordinators(conn=Depends(get_db)):
    rows = conn.execute(
        "SELECT * FROM coordinators ORDER BY created_at DESC"
    ).fetchall()
    return {"count": len(rows), "coordinators": [_serialize(r) for r in rows]}


@router.post("")
def create_coordinator(body: CoordinatorCreate, conn=Depends(get_db)):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name is required.")
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
            coord_id, username, name, body.role, body.constituency,
            body.home_ward, phone, now_iso(),
        ),
    )
    row = conn.execute("SELECT * FROM coordinators WHERE id = ?", (coord_id,)).fetchone()
    return _serialize(row)


@router.patch("/{username}")
def update_coordinator(username: str, body: CoordinatorUpdate, conn=Depends(get_db)):
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ?", (username.lower(),)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Coordinator not found.")

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
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ?", (username.lower(),)
    ).fetchone()
    return _serialize(row)


@router.delete("/{username}")
def delete_coordinator(username: str, conn=Depends(get_db)):
    row = conn.execute(
        "SELECT 1 FROM coordinators WHERE username = ?", (username.lower(),)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Coordinator not found.")
    conn.execute("DELETE FROM coordinators WHERE username = ?", (username.lower(),))
    return {"deleted": username.lower()}
