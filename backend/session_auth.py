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
            "INSERT INTO app_secrets (key, value) VALUES ('session', ?) "
            "ON CONFLICT DO NOTHING",
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


def new_stamp() -> str:
    """A fresh sign-in stamp, recorded on the account and sealed into its token.

    This is what makes signing in somewhere else end the older session. The
    token is self-contained and the server keeps no session table, so without a
    value to compare against, every token ever minted stays valid until it
    expires — up to 180 days — and a new sign-in could not revoke the old
    device. Storing the newest stamp means exactly one token per account
    verifies: the most recent one.
    """
    return secrets.token_hex(8)


def issue(kind: str, subject: str, stamp: str = "") -> str:
    """Mint a token for a verified citizen (user id) or coordinator (username).

    [stamp] is the value just written to the account. Tokens minted before
    stamps existed carry none and are accepted until that account next signs
    in, which is the point at which older devices should drop out anyway.
    """
    days = CITIZEN_DAYS if kind == "citizen" else COORDINATOR_DAYS
    payload = json.dumps(
        {"k": kind, "s": subject, "exp": int(time.time()) + days * 86400,
         "v": stamp},
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


def corporation_switched_off(conn, constituency: str, status_code: int = 401) -> None:
    """Refuse a coordinator whose corporation is not the live one.

    401 mid-session so the app clears the session and returns to sign-in,
    where the login refuses them (403) with the same explanation
    (routers/auth.coordinator_login).
    """
    import corporations

    mine = corporations.corporation_of_constituency(constituency)
    active = corporations.active_id(conn)
    if mine is not None and mine != active:
        raise HTTPException(
            status_code=status_code,
            detail=(f"The app is serving {corporations.get(active)['short_name']} now, "
                    f"so {corporations.get(mine)['short_name']} coordinator accounts "
                    "are paused. Contact the MLA office."),
            headers={"WWW-Authenticate": "Bearer"} if status_code == 401 else None,
        )


def _signed_in_elsewhere() -> None:
    """This account signed in on another device; this token is the older one.

    401 rather than 403 on purpose: the clients already treat 401 as "clear the
    local session and go to sign-in", which is exactly the required behaviour.
    """
    raise HTTPException(
        status_code=401,
        detail="You signed in on another device. Please sign in again here.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _stamp_matches(stored, presented: str) -> bool:
    """An account with no stored stamp predates this and accepts any token."""
    current = (stored or "")
    return not current or current == (presented or "")


def _read(authorization: str, x_session_token: str):
    token = (x_session_token or "").strip()
    if not token and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    return _decode(token) if token else None


def _citizen(conn, user_id: str, stamp: str = "") -> str:
    # A token outlives the account it names, so a deleted account lands here.
    row = conn.execute(
        "SELECT session_epoch FROM users WHERE id = ?", (user_id,)
    ).fetchone() if user_id else None
    if row is None:
        _sign_in_again()
    if not _stamp_matches(row["session_epoch"], stamp):
        _signed_in_elsewhere()
    return user_id


def _coordinator(conn, username: str, stamp: str = "") -> str:
    who = (username or "").strip().lower()
    row = conn.execute(
        "SELECT status, session_epoch, constituency FROM coordinators WHERE LOWER(username) = ?",
        (who,),
    ).fetchone() if who else None
    if row is None:
        _sign_in_again()
    if not _stamp_matches(row["session_epoch"], stamp):
        _signed_in_elsewhere()
    # A coordinator works only while their corporation is the live one; the
    # MLA office switching corporations signs the other one's staff out.
    corporation_switched_off(conn, row["constituency"])
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
    return _citizen(conn, str(data.get("s") or ""), str(data.get("v") or ""))


def coordinator_session(
    authorization: str = Header(default=""),
    x_session_token: str = Header(default=""),
    conn=Depends(get_db),
) -> str:
    """Dependency: the signed-in coordinator's username (lower-case), or 401."""
    data = _read(authorization, x_session_token)
    if not data or data.get("k") != "coordinator":
        _sign_in_again()
    return _coordinator(conn, str(data.get("s") or ""), str(data.get("v") or ""))


def any_session(
    authorization: str = Header(default=""),
    x_session_token: str = Header(default=""),
    conn=Depends(get_db),
) -> tuple:
    """Dependency for endpoints both roles use: (kind, account), or 401."""
    data = _read(authorization, x_session_token)
    kind = (data or {}).get("k")
    subject = str((data or {}).get("s") or "")
    stamp = str((data or {}).get("v") or "")
    if kind == "citizen":
        return kind, _citizen(conn, subject, stamp)
    if kind == "coordinator":
        return kind, _coordinator(conn, subject, stamp)
    _sign_in_again()


#: What a client sends instead of repeating its own account id.
SELF = "me"


def resolve_self(user_id: str, session_uid: str) -> str:
    """Accept the literal "me" in place of the caller's own account id.

    Several endpoints take the account in the URL path, where an empty value
    cannot be sent — so a client had to repeat an id it also stores locally,
    and any drift between that copy and the token meant every one of those
    calls was refused. "me" lets the caller name itself without holding a
    second copy of its identity that can go stale.
    """
    return session_uid if (user_id or "").strip() == SELF else user_id


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
    rid = resolve_self((recipient_id or "").strip(), account)
    same = rid.lower() == account if kind == "coordinator" else rid == account
    if (recipient_type or "").strip() != kind or not same:
        raise HTTPException(
            status_code=403, detail="Those notifications belong to another account."
        )
