"""
routers/coordinators_admin.py
-----------------------------
Admin-console CRUD for constituency-staff (coordinator) accounts.

The web admin's "Coordinators" page and the coordinator app's sign-in both
work against this table — coordinators created here (username / temp password
/ role / constituency / home ward / must_change_password) are the ONLY
accounts that can log into the mobile coordinator console.
"""

import secrets
import string

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from database import get_db
from utils import new_id, now_iso

router = APIRouter(prefix="/api/admin/coordinators", tags=["admin-coordinators"])


def _serialize(row) -> dict:
    d = dict(row)
    d["must_change_password"] = bool(d.get("must_change_password", 0))
    # Never leak passwords through admin listings.
    d.pop("password", None)
    return d


class CoordinatorCreate(BaseModel):
    name: str
    username: str
    password: str
    role: str
    constituency: str
    home_ward: str
    must_change_password: bool = True


class CoordinatorUpdate(BaseModel):
    name: str | None = None
    role: str | None = None
    constituency: str | None = None
    home_ward: str | None = None
    password: str | None = None
    must_change_password: bool | None = None
    status: str | None = None  # 'active' | 'disabled'


@router.get("")
def list_coordinators(conn=Depends(get_db)):
    rows = conn.execute(
        "SELECT * FROM coordinators ORDER BY created_at DESC"
    ).fetchall()
    return {"count": len(rows), "coordinators": [_serialize(r) for r in rows]}


@router.post("")
def create_coordinator(body: CoordinatorCreate, conn=Depends(get_db)):
    username = body.username.strip().lower()
    if not username or " " in username:
        raise HTTPException(status_code=400, detail="Username must be lowercase, no spaces.")
    if len(body.password) < 4:
        raise HTTPException(status_code=400, detail="Password must be at least 4 characters.")
    if not body.name.strip():
        raise HTTPException(status_code=400, detail="Name is required.")

    existing = conn.execute(
        "SELECT 1 FROM coordinators WHERE username = ?", (username,)
    ).fetchone()
    if existing:
        raise HTTPException(status_code=409, detail=f"Username @{username} already exists.")

    coord_id = new_id()
    conn.execute(
        """INSERT INTO coordinators
           (id, username, password, name, role, constituency, home_ward,
            must_change_password, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            coord_id, username, body.password, body.name.strip(),
            body.role, body.constituency, body.home_ward,
            1 if body.must_change_password else 0,
            now_iso(),
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
        raise HTTPException(status_code=404, detail=f"Coordinator @{username} not found.")

    updates, params = [], []
    for col, val in [
        ("name", body.name),
        ("role", body.role),
        ("constituency", body.constituency),
        ("home_ward", body.home_ward),
        ("password", body.password),
        ("status", body.status.lower() if body.status else None),
    ]:
        if val is not None:
            updates.append(f"{col} = ?")
            params.append(val)
    if body.must_change_password is not None:
        updates.append("must_change_password = ?")
        params.append(1 if body.must_change_password else 0)

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
        raise HTTPException(status_code=404, detail=f"Coordinator @{username} not found.")
    conn.execute("DELETE FROM coordinators WHERE username = ?", (username.lower(),))
    return {"deleted": username.lower()}


def _random_password(n: int = 10) -> str:
    """Helper for `POST /generate-password`."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


@router.get("/generate-password")
def generate_password():
    """Small helper the admin form uses to fill a suggested temp password."""
    return {"password": _random_password(10)}
