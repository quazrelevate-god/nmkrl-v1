"""
admin_auth.py
-------------
Authentication for the admin console.

Every /admin page and every /api/admin/* endpoint used to be open to anyone
who reached the URL — including creating coordinator accounts and resetting
their passwords. This closes that with the smallest thing that is genuinely a
lock rather than the appearance of one: one shared operator account, and a
signed, expiring token that the server verifies on every admin request.

The token is an HMAC over its own payload, so it cannot be edited or forged
without the server secret, and it carries its own expiry. There is no session
table to keep in step — a token is valid because the maths says so.

Configure with:
    ADMIN_USERNAME   default 'admin'
    ADMIN_PASSWORD   default 'nammakural' — CHANGE THIS before the app is
                     reachable from outside the demo laptop
    ADMIN_SECRET     signing key; a random one is generated per boot when
                     unset, which simply means a restart signs everyone out
    ADMIN_TOKEN_HOURS  default 12
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time

from fastapi import Header, HTTPException

ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "nammakural")
TOKEN_HOURS = int(os.getenv("ADMIN_TOKEN_HOURS", "12"))

# A per-boot random secret is the safe default: a shipped constant would be
# public the moment the repository is, and every deploy that cares can set one.
_SECRET = (os.getenv("ADMIN_SECRET") or secrets.token_hex(32)).encode("utf-8")


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _sign(payload: bytes) -> str:
    return _b64(hmac.new(_SECRET, payload, hashlib.sha256).digest())


def issue_token(username: str) -> dict:
    """Mint a signed token for a verified operator."""
    expires = int(time.time()) + TOKEN_HOURS * 3600
    payload = json.dumps({"u": username, "exp": expires}, separators=(",", ":")).encode()
    token = f"{_b64(payload)}.{_sign(payload)}"
    return {"token": token, "username": username, "expires_at": expires}


def verify_credentials(username: str, password: str) -> bool:
    """Constant-time credential check, so a wrong guess leaks no timing."""
    return (
        hmac.compare_digest((username or "").strip().lower(), ADMIN_USERNAME.lower())
        and hmac.compare_digest(password or "", ADMIN_PASSWORD)
    )


def _decode(token: str) -> dict | None:
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


async def require_admin(
    x_admin_token: str = Header(default=""),
    authorization: str = Header(default=""),
) -> str:
    """FastAPI dependency guarding the admin surface.

    Accepts the token in `X-Admin-Token` or as a bearer token, and answers 401
    so the console can send the operator back to the sign-in page rather than
    showing an empty dashboard.
    """
    token = x_admin_token.strip()
    if not token and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    data = _decode(token) if token else None
    if data is None:
        raise HTTPException(
            status_code=401,
            detail="Admin sign-in required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return data["u"]
