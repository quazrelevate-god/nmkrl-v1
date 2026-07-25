"""
routers/auth.py
---------------
Phase-1 citizen authentication: name + OTP-verified phone number (the OTP is
a static mock, verified client-side in phase 1).

  POST /api/auth/login   (name, phone)
      * phone found  AND name matches  → authenticated, returns the profile
      * phone found  BUT name differs  → 401 (number registered to another name)
      * phone not found                → creates the profile, authenticated

Every subsequent action (report / upvote / verify / history) carries the
returned user id, so all activity belongs to the authenticated account.
"""

import re

from fastapi import APIRouter, Depends, Form, HTTPException

from database import get_db
from utils import new_id, now_iso

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _normalise_phone(raw: str) -> str:
    """Digits only, last 10 (Indian mobile) — '+91 98840 12345' → '9884012345'."""
    digits = re.sub(r"\D", "", raw or "")
    return digits[-10:] if len(digits) >= 10 else digits


def _serialize_user(row) -> dict:
    return {"id": row["id"], "name": row["name"], "phone": row["phone"]}


@router.post("/login")
def citizen_login(
    name: str = Form(...),
    phone: str = Form(...),
    conn=Depends(get_db),
):
    clean_name = " ".join(name.split())
    clean_phone = _normalise_phone(phone)
    if len(clean_name) < 2:
        raise HTTPException(status_code=400, detail="Enter your full name.")
    if len(clean_phone) != 10:
        raise HTTPException(
            status_code=400, detail="Enter a valid 10-digit mobile number."
        )

    row = conn.execute(
        "SELECT * FROM users WHERE phone = ?", (clean_phone,)
    ).fetchone()

    if row is not None:
        if row["name"].strip().lower() != clean_name.lower():
            raise HTTPException(
                status_code=401,
                detail=(
                    "This mobile number is already registered under a different "
                    "name. Enter the name it was registered with."
                ),
            )
        return {**_serialize_user(row), "created": False}

    user_id = new_id()
    conn.execute(
        "INSERT INTO users (id, name, phone, created_at) VALUES (?, ?, ?, ?)",
        (user_id, clean_name, clean_phone, now_iso()),
    )
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {**_serialize_user(row), "created": True}


@router.post("/coordinator/login")
def coordinator_login(
    username: str = Form(...),
    password: str = Form(...),
    conn=Depends(get_db),
):
    """
    Sign in against the admin-managed coordinators table. Returns the full
    profile (minus password) so the mobile app can pin the constituency and
    default the ward switcher to home_ward.
    """
    clean_user = (username or "").strip().lower()
    if not clean_user or not password:
        raise HTTPException(status_code=400, detail="Enter username and password.")
    row = conn.execute(
        "SELECT * FROM coordinators WHERE username = ?", (clean_user,)
    ).fetchone()
    if row is None or row["password"] != password:
        raise HTTPException(status_code=401, detail="Invalid username or password.")
    return {
        "id": row["id"],
        "username": row["username"],
        "name": row["name"],
        "role": row["role"],
        "constituency": row["constituency"],
        "home_ward": row["home_ward"],
        "must_change_password": bool(row["must_change_password"]),
    }
