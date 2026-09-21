"""
routers/auth.py
---------------
Citizen and coordinator sign-in, and citizen account deletion.

  POST /api/auth/request-otp  (phone)
      Sends a one-time code by SMS through APM Technologies. The code is never
      returned to the caller in production; if the SMS cannot be sent, the
      request fails. Two deliberate exceptions, both off unless configured:
        * ALLOW_DEV_OTP=1 — local development without an SMS key. The server
          makes a code and returns it as ``dev_otp``.
        * REVIEW_LOGIN_PHONE + REVIEW_LOGIN_OTP — one fixed number and code for
          app-store reviewers, who cannot receive an Indian SMS. No SMS is
          sent for that number.
      Requests are throttled per number: one every 30 seconds, five an hour.

  POST /api/auth/login   (name, phone, otp)
      Verifies the code, then:
      * phone found  AND name matches  → authenticated
      * phone found  BUT name differs  → 401 (number registered to another name)
      * phone not found                → creates the account, authenticated
      Returns the profile and a signed session token (session_auth.py). Every
      personal endpoint takes the account from that token.

  POST   /api/auth/coordinator/request-otp  (name, phone) → sends a login code
  POST   /api/auth/coordinator/login  (name, phone, otp) → profile + token
  POST   /api/auth/set-pin, /verify-pin                    → citizen session

  DELETE /api/auth/account            delete the signed-in citizen's account
  POST   /api/auth/account/delete     (phone, otp) the same, for the web
                                      deletion page, proven by a fresh code
"""

import hashlib
import hmac
import os
import re
import secrets
import sys
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, Form, HTTPException

import session_auth
from database import get_db
from session_auth import citizen_session, require_same_citizen
from utils import new_id, now_iso, remove_upload

router = APIRouter(prefix="/api/auth", tags=["auth"])

OTP_TTL_MINUTES = 5
OTP_MAX_ATTEMPTS = 5
OTP_COOLDOWN_SECONDS = 30
OTP_MAX_PER_HOUR = 5
APM_SMS_URL = "https://sms.apmtechnologies.in/api/Home/Registration"


def _flag(name: str) -> bool:
    return (os.getenv(name) or "").strip().lower() in ("1", "true", "yes")


def _normalise_phone(raw: str) -> str:
    """Digits only, last 10 (Indian mobile) — '+91 98840 12345' → '9884012345'."""
    digits = re.sub(r"\D", "", raw or "")
    return digits[-10:] if len(digits) >= 10 else digits


def _hash_otp(otp: str) -> str:
    return hashlib.sha256(otp.encode("utf-8")).hexdigest()


def _parse_ts(value):
    try:
        ts = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None
    return ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)


def _serialize_user(row) -> dict:
    # has_pin decides where the app sends the user after login: straight in, or
    # through the "create your PIN" screen. Accounts created before PINs
    # existed report False and are taken through the same setup.
    return {
        "id": row["id"],
        "name": row["name"],
        "phone": row["phone"],
        "has_pin": bool((row["pin_hash"] or "").strip()),
    }


def _send_otp_via_apm(phone10: str) -> str | None:
    """Call APM Technologies to generate + SMS an OTP. Returns the OTP string,
    or None when no API key is configured. Raises HTTPException on gateway
    failure."""
    api_key = os.getenv("APM_SMS_API_KEY")
    if not api_key:
        return None
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


def _review_login():
    """The app-store reviewer's fixed number and code, when both are configured."""
    phone = _normalise_phone(os.getenv("REVIEW_LOGIN_PHONE", ""))
    code = (os.getenv("REVIEW_LOGIN_OTP") or "").strip()
    if len(phone) == 10 and code.isdigit() and len(code) >= 4:
        return phone, code
    return None, None


def _throttle(conn, phone10: str):
    """Rate-limit code requests for one number. Returns the (window_start,
    window_count) to store with the new code.

    Each request costs an SMS and resets the guess counter, so without a limit
    a script could both run up the SMS bill and try codes indefinitely.
    """
    now = datetime.now(timezone.utc)
    row = conn.execute(
        "SELECT created_at, window_start, window_count FROM otp_codes WHERE phone = ?",
        (phone10,),
    ).fetchone()
    if row is None:
        return now.isoformat(), 1
    last = _parse_ts(row["created_at"])
    if last and (now - last).total_seconds() < OTP_COOLDOWN_SECONDS:
        raise HTTPException(
            status_code=429,
            detail="Please wait a few seconds before asking for another code.",
        )
    start = _parse_ts(row["window_start"])
    if start is None or now - start > timedelta(hours=1):
        return now.isoformat(), 1
    count = row["window_count"] or 0
    if count >= OTP_MAX_PER_HOUR:
        raise HTTPException(
            status_code=429,
            detail="Too many codes requested for this number. Try again in an hour.",
        )
    return row["window_start"], count + 1


@router.post("/request-otp")
def request_otp(phone: str = Form(...), name: str = Form(""), conn=Depends(get_db)):
    """Generate and send a one-time code for [phone].

    When a name is supplied, the number/name pairing is checked *before* the
    code is sent: an SMS to a number already registered under a different name
    would only be wasted, since login would reject it anyway. Catching it here
    means the citizen sees "that number is under a different name" up front,
    not after they have typed a code. Name omitted keeps older clients working.
    """
    clean_phone = _normalise_phone(phone)
    if len(clean_phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")

    clean_name = " ".join((name or "").split())
    if clean_name:
        existing = conn.execute(
            "SELECT name FROM users WHERE phone = ?", (clean_phone,)
        ).fetchone()
        if existing is not None and existing["name"].strip().lower() != clean_name.lower():
            raise HTTPException(
                status_code=401,
                detail=(
                    "This mobile number is already registered under a different "
                    "name. Enter the name it was registered with."
                ),
            )

    window_start, window_count = _throttle(conn, clean_phone)
    review_phone, review_code = _review_login()
    dev_mode = _flag("ALLOW_DEV_OTP")
    dummy = False

    if review_phone and clean_phone == review_phone:
        otp = review_code
    else:
        # The code used to come back in the response whenever the SMS could not
        # be sent — including when the gateway was merely down or out of
        # credit in production. At that moment anyone could sign in as anyone
        # by typing their number. Outside development, a failed send now fails.
        try:
            otp = _send_otp_via_apm(clean_phone)
        except HTTPException as e:
            print(f"[auth] APM gateway failed ({e.detail})", file=sys.stderr)
            if not dev_mode:
                raise HTTPException(
                    status_code=503,
                    detail="We couldn't send the code right now. Please try again in a few minutes.",
                )
            otp = None
        if otp is None:
            if not dev_mode:
                print("[auth] no APM_SMS_API_KEY and ALLOW_DEV_OTP is off", file=sys.stderr)
                raise HTTPException(
                    status_code=503,
                    detail="SMS sign-in is not available right now. Please try again later.",
                )
            otp = f"{secrets.randbelow(1_000_000):06d}"
            dummy = True

    expires = (datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)).isoformat()
    conn.execute(
        """INSERT INTO otp_codes
               (phone, otp_hash, expires_at, attempts, created_at, window_start, window_count)
           VALUES (?, ?, ?, 0, ?, ?, ?)
           ON CONFLICT(phone) DO UPDATE SET
             otp_hash = excluded.otp_hash,
             expires_at = excluded.expires_at,
             attempts = 0,
             created_at = excluded.created_at,
             window_start = excluded.window_start,
             window_count = excluded.window_count""",
        (clean_phone, _hash_otp(otp), expires, now_iso(), window_start, window_count),
    )
    out = {"sent": True, "dummy": dummy, "ttl_minutes": OTP_TTL_MINUTES}
    if dummy:
        out["dev_otp"] = otp  # ALLOW_DEV_OTP only
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
    expired = (_parse_ts(row["expires_at"]) or datetime.min.replace(tzinfo=timezone.utc)) \
        < datetime.now(timezone.utc)
    if expired:
        raise HTTPException(status_code=400, detail="OTP expired. Request a new one.")
    if not hmac.compare_digest(_hash_otp(otp.strip()), row["otp_hash"]):
        conn.execute(
            "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?", (phone10,)
        )
        # Commit before raising: the request's connection rolls back on an
        # exception, which quietly undid this counter and left guesses unlimited.
        conn.commit()
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
        stamp = session_auth.new_stamp()
        conn.execute(
            "UPDATE users SET session_epoch = ? WHERE id = ?", (stamp, row["id"])
        )
        return {
            **_serialize_user(row),
            "created": False,
            "token": session_auth.issue("citizen", row["id"], stamp),
        }

    user_id = new_id()
    conn.execute(
        "INSERT INTO users (id, name, phone, created_at) VALUES (?, ?, ?, ?)",
        (user_id, clean_name, clean_phone, now_iso()),
    )
    stamp = session_auth.new_stamp()
    conn.execute(
        "UPDATE users SET session_epoch = ? WHERE id = ?", (stamp, user_id)
    )
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {
        **_serialize_user(row),
        "created": True,
        "token": session_auth.issue("citizen", user_id, stamp),
    }


def _corporation_of(constituency) -> str | None:
    import corporations

    return corporations.corporation_of_constituency(constituency)


def coordinator_profile(row) -> dict:
    """The signed-in coordinator's own profile, as the app displays it.

    One shape for both the login response and GET /api/coordinator/me, so the
    two cannot drift. It carries the admin-uploaded photo: the app used to be
    sent everything except that, so a coordinator never saw the picture the
    MLA office had set for them.
    """
    return {
        "id": row["id"],
        "username": row["username"],
        "name": row["name"],
        "role": row["role"],
        "constituency": row["constituency"],
        "corporation": _corporation_of(row["constituency"]),
        "home_ward": row["home_ward"],
        "photo_url": row["photo_url"] or "",
        "must_change_password": False,
    }


def _match_coordinator(conn, name: str, phone10: str):
    """Find the coordinator whose mobile is [phone10] and confirm the name.

    Coordinators sign in with name + mobile + OTP, like citizens, but never
    auto-register: only an admin-created account can get in. The 'no such
    account' and 'name does not match' cases share one message so neither
    reveals which numbers are registered.
    """
    row = conn.execute(
        "SELECT * FROM coordinators WHERE phone = ? AND phone <> ''", (phone10,)
    ).fetchone()
    clean_name = " ".join((name or "").split())
    if row is None or row["name"].strip().lower() != clean_name.lower():
        raise HTTPException(
            status_code=401,
            detail="No coordinator account matches that name and mobile number.",
        )
    if (row["status"] or "active").lower() != "active":
        raise HTTPException(
            status_code=403,
            detail="This account has been disabled. Contact the MLA office.",
        )
    return row


@router.post("/coordinator/request-otp")
def coordinator_request_otp(
    name: str = Form(...), phone: str = Form(...), conn=Depends(get_db)
):
    """Send a login code to a coordinator — only if the name + mobile match an
    admin-created account, and before any SMS is spent."""
    clean_phone = _normalise_phone(phone)
    if len(clean_phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")
    row = _match_coordinator(conn, name, clean_phone)  # 401/403 before a code is sent
    # Nor for an account whose corporation the console has switched away from.
    session_auth.corporation_switched_off(conn, row["constituency"], status_code=403)

    window_start, window_count = _throttle(conn, clean_phone)
    dev_mode = _flag("ALLOW_DEV_OTP")
    dummy = False
    try:
        otp = _send_otp_via_apm(clean_phone)
    except HTTPException as e:
        print(f"[auth] APM gateway failed ({e.detail})", file=sys.stderr)
        if not dev_mode:
            raise HTTPException(
                status_code=503,
                detail="We couldn't send the code right now. Please try again in a few minutes.",
            )
        otp = None
    if otp is None:
        if not dev_mode:
            raise HTTPException(
                status_code=503,
                detail="SMS sign-in is not available right now. Please try again later.",
            )
        otp = f"{secrets.randbelow(1_000_000):06d}"
        dummy = True

    expires = (datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)).isoformat()
    conn.execute(
        """INSERT INTO otp_codes
               (phone, otp_hash, expires_at, attempts, created_at, window_start, window_count)
           VALUES (?, ?, ?, 0, ?, ?, ?)
           ON CONFLICT(phone) DO UPDATE SET
             otp_hash = excluded.otp_hash, expires_at = excluded.expires_at,
             attempts = 0, created_at = excluded.created_at,
             window_start = excluded.window_start, window_count = excluded.window_count""",
        (clean_phone, _hash_otp(otp), expires, now_iso(), window_start, window_count),
    )
    out = {"sent": True, "dummy": dummy, "ttl_minutes": OTP_TTL_MINUTES}
    if dummy:
        out["dev_otp"] = otp
    return out


@router.post("/coordinator/login")
def coordinator_login(
    name: str = Form(...),
    phone: str = Form(...),
    otp: str = Form(...),
    conn=Depends(get_db),
):
    """Verify a coordinator's login code and issue the session token.

    Returns the profile the mobile app needs (constituency + home ward) plus the
    token every coordinator endpoint requires.
    """
    clean_phone = _normalise_phone(phone)
    if len(clean_phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")
    _verify_otp(conn, clean_phone, otp)
    row = _match_coordinator(conn, name, clean_phone)
    session_auth.corporation_switched_off(conn, row["constituency"], status_code=403)
    stamp = session_auth.new_stamp()
    conn.execute(
        "UPDATE coordinators SET session_epoch = ? WHERE id = ?", (stamp, row["id"])
    )
    return {
        **coordinator_profile(row),
        "token": session_auth.issue(
            "coordinator", row["username"].lower(), stamp
        ),
    }


# ── App-open PIN ──────────────────────────────────────────────────────────
#
# The four digits never leave the device. The client sends
# sha256("<user_id>:<pin>") and the server only ever compares strings, so a
# leaked database yields hashes salted per account rather than PINs. Four
# digits is a small space by nature — this is a convenience lock on a device
# the person already holds, not a second factor.


def _clean_hash(value: str) -> str:
    v = (value or "").strip().lower()
    if len(v) != 64 or any(c not in "0123456789abcdef" for c in v):
        raise HTTPException(status_code=400, detail="Malformed PIN.")
    return v


@router.post("/set-pin")
def set_pin(
    pin_hash: str = Form(...),
    user_id: str = Form(""),
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Set or replace the app-open PIN for the signed-in account."""
    require_same_citizen(session_uid, user_id)
    digest = _clean_hash(pin_hash)
    conn.execute("UPDATE users SET pin_hash = ? WHERE id = ?", (digest, session_uid))
    return {"ok": True, "has_pin": True}


@router.post("/verify-pin")
def verify_pin(
    pin_hash: str = Form(...),
    user_id: str = Form(""),
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Check a PIN against the stored hash.

    The app unlocks against its own local copy so it works offline; this is the
    path for a reinstall or a second device, where there is nothing cached yet.
    """
    require_same_citizen(session_uid, user_id)
    digest = _clean_hash(pin_hash)
    row = conn.execute(
        "SELECT pin_hash FROM users WHERE id = ?", (session_uid,)
    ).fetchone()
    stored = (row["pin_hash"] or "").strip()
    if not stored:
        return {"ok": False, "has_pin": False}
    return {"ok": hmac.compare_digest(stored, digest), "has_pin": True}


# ── Account deletion ──────────────────────────────────────────────────────
#
# Google Play requires any app that creates accounts to let people delete them,
# both inside the app and from a web page. Grievances are a public civic record
# and the officials handling them still need the problem, its photo and its
# place, so a deleted account's reports stay — stripped of everything that
# identifies the person: name, phone, account link, their voice recording and
# its transcript, and any petition they attached. Everything else tied to the
# account is removed outright.


def erase_citizen(conn, user_id: str) -> dict:
    user = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if user is None:
        return {"deleted": False, "reports_anonymised": 0}

    reports = conn.execute(
        "SELECT id, audio_url, document_url FROM issues WHERE created_by = ?",
        (user_id,),
    ).fetchall()
    for r in reports:
        remove_upload(r["audio_url"])
        remove_upload(r["document_url"])
    conn.execute(
        """UPDATE issues
              SET created_by = '', name = '', phone = '',
                  audio_url = NULL, transcript = '', transcript_ta = '',
                  document_url = NULL, document_name = '', document_summary = '',
                  notify_reporter = 0
            WHERE created_by = ?""",
        (user_id,),
    )
    conn.execute(
        """UPDATE issue_events SET actor_id = '', audio_url = NULL
            WHERE actor_type = 'citizen' AND actor_id = ?""",
        (user_id,),
    )
    # Their support is withdrawn, so the public counts drop with it. A CASE,
    # not two-argument MAX(): that is SQLite-only (Postgres spells it GREATEST,
    # which SQLite lacks).
    conn.execute(
        """UPDATE issues SET upvotes = CASE WHEN upvotes > 0 THEN upvotes - 1 ELSE 0 END
            WHERE id IN (SELECT issue_id FROM upvotes WHERE user_id = ?)""",
        (user_id,),
    )
    conn.execute("DELETE FROM upvotes WHERE user_id = ?", (user_id,))
    conn.execute("UPDATE verifications SET user_id = '' WHERE user_id = ?", (user_id,))
    conn.execute("DELETE FROM content_reports WHERE reporter_id = ?", (user_id,))
    conn.execute(
        "DELETE FROM notifications WHERE recipient_type = 'citizen' AND recipient_id = ?",
        (user_id,),
    )
    conn.execute(
        "DELETE FROM device_tokens WHERE recipient_type = 'citizen' AND recipient_id = ?",
        (user_id,),
    )
    conn.execute("DELETE FROM otp_codes WHERE phone = ?", (user["phone"],))
    conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
    return {"deleted": True, "reports_anonymised": len(reports)}


@router.delete("/account")
def delete_my_account(
    session_uid: str = Depends(citizen_session),
    conn=Depends(get_db),
):
    """Delete the signed-in citizen's account (the app's "Delete account")."""
    return {"ok": True, **erase_citizen(conn, session_uid)}


@router.post("/account/delete")
def delete_account_with_code(
    phone: str = Form(...),
    otp: str = Form(...),
    conn=Depends(get_db),
):
    """Delete an account from the web deletion page, proven by a fresh code."""
    clean_phone = _normalise_phone(phone)
    if len(clean_phone) != 10:
        raise HTTPException(status_code=400, detail="Enter a valid 10-digit mobile number.")
    _verify_otp(conn, clean_phone, otp)
    user = conn.execute("SELECT id FROM users WHERE phone = ?", (clean_phone,)).fetchone()
    if user is None:
        return {"ok": True, "deleted": False, "reports_anonymised": 0}
    return {"ok": True, **erase_citizen(conn, user["id"])}
