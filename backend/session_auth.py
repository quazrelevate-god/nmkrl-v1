"""
session_auth.py
---------------
Signed sessions for citizens and coordinators.

Every citizen and coordinator endpoint used to take the caller's identity from
the request itself: a ``user_id`` in the form, a ``coordinator`` username in
the query. Nothing checked it. Anyone holding one citizen's id could read
their reports and act as them, and the coordinator queues, which carry every
reporter's name and phone number, needed no sign-in at all.

Signing in now returns a token: an HMAC-signed payload naming the account and
when it expires, the same construction the admin console uses (admin_auth.py).
Endpoints take the account from the token and refuse a request that names a
different one.

The signing key comes from SESSION_SECRET when that is set. Otherwise one is
generated on first use and kept in the database, so it lives on the same
persistent volume as the accounts it signs for. A per-boot key, as admin uses,
would sign every citizen out on each redeploy.

    SESSION_SECRET            optional signing key
    CITIZEN_SESSION_DAYS      default 180
    COORDINATOR_SESSION_DAYS  default 30
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time

from fastapi import Depends, Header, HTTPException

from database import get_connection, get_db

CITIZEN_DAYS = int(os.getenv("CITIZEN_SESSION_DAYS", "180"))
COORDINATOR_DAYS = int(os.getenv("COORDINATOR_SESSION_DAYS", "30"))

_secret_cache = None


def _secret() -> bytes:
    global _secret_cache
    if _secret_cache is not None:
        return _secret_cache
    configured = (os.getenv("SESSION_SECRET") or "").strip()
    if configured:
        _secret_cache = configured.encode("utf-8")
        return _secret_cache
    with get_connection() as conn:
        # Insert-if-absent, then read back: two workers starting together
        # settle on whichever key landed first.
        conn.execute(
            "INSERT OR IGNORE INTO app_secrets (key, value) VALUES ('session', ?)",
            (secrets.token_hex(32),),
        )
        row = conn.execute(
            "SELECT value FROM app_secrets WHERE key = 'session'"
        ).fetchone()
    _secret_cache = row[0].encode("utf-8")
    return _secret_cache


def ensure_ready() -> None:
    """Seed and cache the signing key at startup.

    Called from the app's lifespan so the one-time INSERT into app_secrets
    happens before any request is served — otherwise the first login races its
    own request connection for the write lock.
    """
    _secret()


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _sign(payload: bytes) -> str:
    return _b64(hmac.new(_secret(), payload, hashlib.sha256).digest())


def issue(kind: str, subject: str) -> str:
    """Mint a token for a verified citizen (user id) or coordinator (username)."""
    days = CITIZEN_DAYS if kind == "citizen" else COORDINATOR_DAYS
    payload = json.dumps(
        {"k": kind, "s": subject, "exp": int(time.time()) + days * 86400},
        separators=(",", ":"),
    ).encode("utf-8")
    return f"{_b64(payload)}.{_sign(payload)}"


def _decode(token: str):
    try:
        body, sig = token.split(".", 1)
        payload = _unb64(body)
        if not hmac.compare_digest(sig, _sign(payload)):
            return None  # forged or tampered with
        data = json.loads(payload)
    except Exception:
        return None
    if int(data.get("exp", 0)) < time.time():
        return None  # expired
    return data


def _sign_in_again() -> None:
    raise HTTPException(
        status_code=401,
        detail="Your session has ended. Please sign in again.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _read(authorization: str, x_session_token: str):
    token = (x_session_token or "").strip()
    if not token and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    return _decode(token) if token else None


def _citizen(conn, user_id: str) -> str:
    # A token outlives the account it names, so a deleted account lands here.
    if not user_id or conn.execute(
        "SELECT 1 FROM users WHERE id = ?", (user_id,)
    ).fetchone() is None:
        _sign_in_again()
    return user_id


def _coordinator(conn, username: str) -> str:
    who = (username or "").strip().lower()
    row = conn.execute(
        "SELECT status FROM coordinators WHERE LOWER(username) = ?", (who,)
    ).fetchone() if who else None
    if row is None:
        _sign_in_again()
    # Checked on every request, so disabling an account in the admin console
    # takes effect on the coordinator's next tap.
    if (row[0] or "active").lower() != "active":
        raise HTTPException(
            status_code=403,
            detail="This account has been disabled. Contact the MLA office.",
        )
    return who


def citizen_session(
    authorization: str = Header(default=""),
    x_session_token: str = Header(default=""),
    conn=Depends(get_db),
) -> str:
    """Dependency: the signed-in citizen's user id, or 401."""
    data = _read(authorization, x_session_token)
    if not data or data.get("k") != "citizen":
        _sign_in_again()
    return _citizen(conn, str(data.get("s") or ""))


def coordinator_session(
    authorization: str = Header(default=""),
    x_session_token: str = Header(default=""),
    conn=Depends(get_db),
) -> str:
    """Dependency: the signed-in coordinator's username (lower-case), or 401."""
    data = _read(authorization, x_session_token)
    if not data or data.get("k") != "coordinator":
        _sign_in_again()
    return _coordinator(conn, str(data.get("s") or ""))


def any_session(
    authorization: str = Header(default=""),
    x_session_token: str = Header(default=""),
    conn=Depends(get_db),
) -> tuple:
    """Dependency for endpoints both roles use: (kind, account), or 401."""
    data = _read(authorization, x_session_token)
    kind = (data or {}).get("k")
    subject = str((data or {}).get("s") or "")
    if kind == "citizen":
        return kind, _citizen(conn, subject)
    if kind == "coordinator":
        return kind, _coordinator(conn, subject)
    _sign_in_again()


def require_same_citizen(session_uid: str, user_id: str) -> None:
    """Refuse a request that names an account other than the signed-in one.

    An empty ``user_id`` is accepted: the session speaks for the caller, and
    the field survives only so older clients that still send it keep working.
    """
    if user_id and user_id.strip() != session_uid:
        raise HTTPException(status_code=403, detail="That belongs to another account.")


def require_same_coordinator(session_username: str, username: str) -> str:
    """As require_same_citizen, for coordinators. Returns the acting username."""
    who = (username or "").strip().lower()
    if who and who != session_username:
        raise HTTPException(
            status_code=403, detail="That belongs to another coordinator account."
        )
    return session_username


def require_recipient(session: tuple, recipient_type: str, recipient_id: str) -> None:
    """Notifications and push tokens may only be read or bound by their owner."""
    kind, account = session
    rid = (recipient_id or "").strip()
    same = rid.lower() == account if kind == "coordinator" else rid == account
    if (recipient_type or "").strip() != kind or not same:
        raise HTTPException(
            status_code=403, detail="Those notifications belong to another account."
        )
