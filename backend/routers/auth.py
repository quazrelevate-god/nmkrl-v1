"""
routers/auth.py
---------------
Phase-1 citizen authentication: name + SMS-OTP-verified phone number.

  POST /api/auth/request-otp  (phone)
      Sends a real OTP via the APM Technologies SMS gateway when
      APM_SMS_API_KEY is configured; otherwise runs in DUMMY mode (server
      generates a 6-digit code and returns it in the response for testing).

  POST /api/auth/login   (name, phone, otp)
      Verifies the OTP first, then:
      * phone found  AND name matches  → authenticated, returns the profile
      * phone found  BUT name differs  → 401 (number registered to another name)
      * phone not found                → creates the profile, authenticated

Every subsequent action (report / upvote / verify / history) carries the
returned user id, so all activity belongs to the authenticated account.
"""

import hashlib
import os
import random
import re
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, Form, HTTPException

from database import get_db
from utils import new_id, now_iso

router = APIRouter(prefix="/api/auth", tags=["auth"])

OTP_TTL_MINUTES = 5
OTP_MAX_ATTEMPTS = 5
APM_SMS_URL = "https://sms.apmtechnologies.in/api/Home/Registration"


def _normalise_phone(raw: str) -> str:
    """Digits only, last 10 (Indian mobile) — '+91 98840 12345' → '9884012345'."""
    digits = re.sub(r"\D", "", raw or "")
    return digits[-10:] if len(digits) >= 10 else digits


def _hash_otp(otp: str) -> str:
    return hashlib.sha256(otp.encode("utf-8")).hexdigest()


def _serialize_user(row) -> dict:
    return {"id": row["id"], "name": row["name"], "phone": row["phone"]}


def _send_otp_via_apm(phone10: str) -> str | None:
    """Call APM Technologies to generate + SMS an OTP. Returns the OTP string,
    or None when no API key is configured (dummy mode). Raises HTTPException
    on gateway failure."""
    api_key = os.getenv("APM_SMS_API_KEY")
    if not api_key:
        return None  # dummy mode — caller generates locally
    try:
        with httpx.Client(timeout=10) as client:
            resp = client.post(
                APM_SMS_URL,
                params={"ApiKey": api_key, "PhoneNumber": phone10},
            )
        resp.raise_for_status()
        otp = resp.text.strip().strip('"')
        if not otp or not otp.isdigit():
            raise HTTPException(status_code=502, detail="SMS gateway did not return an OTP.")
        return otp
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"SMS gateway error: {e}")


@router.post("/request-otp")
def request_otp(phone: str = Form(...), conn=Depends(get_db)):
    """Generate + send an OTP for [phone]. In dummy mode the code is returned
    in the response (dev_otp) so the flow works without a live SMS key."""
    clean_phone = _normalise_phone(phone)
    if len(clean_phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")

    apm_otp = _send_otp_via_apm(clean_phone)
    dummy = apm_otp is None
    otp = apm_otp if apm_otp else f"{random.randint(0, 999999):06d}"

    expires = (datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)).isoformat()
    conn.execute(
        """INSERT INTO otp_codes (phone, otp_hash, expires_at, attempts, created_at)
           VALUES (?, ?, ?, 0, ?)
           ON CONFLICT(phone) DO UPDATE SET
             otp_hash = excluded.otp_hash,
             expires_at = excluded.expires_at,
             attempts = 0,
             created_at = excluded.created_at""",
        (clean_phone, _hash_otp(otp), expires, now_iso()),
    )
    out = {"sent": True, "dummy": dummy, "ttl_minutes": OTP_TTL_MINUTES}
    if dummy:
        # Surfaced ONLY in dummy mode (no live SMS) so the demo flow works.
        out["dev_otp"] = otp
    return out


def _verify_otp(conn, phone10: str, otp: str) -> None:
    """Raise HTTPException unless [otp] matches the stored, unexpired hash."""
    row = conn.execute(
        "SELECT * FROM otp_codes WHERE phone = ?", (phone10,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=400, detail="Request an OTP first.")
    if row["attempts"] >= OTP_MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many attempts. Request a new OTP.")
    try:
        expired = datetime.fromisoformat(row["expires_at"]) < datetime.now(timezone.utc)
    except ValueError:
        expired = True
    if expired:
        raise HTTPException(status_code=400, detail="OTP expired. Request a new one.")
    if _hash_otp(otp.strip()) != row["otp_hash"]:
        conn.execute(
            "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?", (phone10,)
        )
        raise HTTPException(status_code=401, detail="Incorrect OTP.")
    # Consume the challenge on success.
    conn.execute("DELETE FROM otp_codes WHERE phone = ?", (phone10,))


@router.post("/login")
def citizen_login(
    name: str = Form(...),
    phone: str = Form(...),
    otp: str = Form(...),
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

    # Gate the whole login on a valid, unexpired OTP for this phone.
    _verify_otp(conn, clean_phone, otp)

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
