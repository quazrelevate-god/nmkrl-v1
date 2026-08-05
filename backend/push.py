"""
push.py
-------
Firebase Cloud Messaging delivery, so a grievance update reaches a citizen or
coordinator whose app is backgrounded or closed. The DB row written by
`routers/notifications._insert()` remains the source of truth — this is a second
delivery channel layered on top of it, never a replacement.

Configuration (Railway variables, never committed):

    FCM_SERVICE_ACCOUNT_JSON   the service-account key JSON, verbatim
    FCM_PROJECT_ID             e.g. nammakural-2927f

With either unset, `send_to_recipient()` is a silent no-op — local dev and any
deploy without credentials keep working exactly as before, on polling alone.

Notes
  * FCM's legacy server-key API was retired in 2024; this uses HTTP v1, which
    needs an OAuth2 access token minted from the service account.
  * Messages carry a `notification` block on purpose. That is what lets Android
    render them from the system tray with our process dead — a data-only
    message would need the app alive and would be dropped by the aggressive
    OEM battery managers common on our users' devices.
  * Android force-stop still suppresses delivery until the app is reopened.
    That is an OS guarantee and cannot be worked around.
"""

from __future__ import annotations

import json
import os
import threading

import httpx

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

# Android notification channel created by the Flutter client. Must match
# `_kChannelId` in mobile/lib/data/push_service.dart or heads-up banners and
# sound are silently dropped on Android 8+.
_CHANNEL_ID = "nk_alerts"

_creds = None
_creds_lock = threading.Lock()


def _project_id() -> str:
    return (os.environ.get("FCM_PROJECT_ID") or "").strip()


def _access_token() -> str | None:
    """OAuth2 bearer for the FCM v1 API, refreshed as it expires."""
    raw = os.environ.get("FCM_SERVICE_ACCOUNT_JSON")
    if not raw or not _project_id():
        return None
    global _creds
    try:
        with _creds_lock:
            if _creds is None:
                # Imported lazily so a deploy without push configured does not
                # need google-auth installed at all.
                from google.oauth2 import service_account

                _creds = service_account.Credentials.from_service_account_info(
                    json.loads(raw), scopes=[_SCOPE]
                )
            if not _creds.valid:
                from google.auth.transport.requests import Request

                _creds.refresh(Request())
            return _creds.token
    except Exception as exc:  # bad key, clock skew, no network — never fatal
        print(f"[push] could not mint access token: {exc}")
        return None


def _tokens_for(conn, recipient_type: str, recipient_id: str) -> list[str]:
    rows = conn.execute(
        "SELECT token FROM device_tokens WHERE recipient_type = ? "
        "AND recipient_id = ?",
        (recipient_type, str(recipient_id)),
    ).fetchall()
    return [r["token"] for r in rows]


def _drop_token(conn, token: str) -> None:
    """Forget a token FCM has told us is dead (app uninstalled / reinstalled)."""
    try:
        conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))
        conn.commit()
    except Exception:
        pass


def _post(conn, token: str, title: str, body: str, data: dict) -> None:
    bearer = _access_token()
    if not bearer:
        return
    payload = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            # All values must be strings — FCM rejects other JSON types here.
            "data": {k: str(v) for k, v in data.items()},
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": _CHANNEL_ID},
            },
        }
    }
    try:
        res = httpx.post(
            _ENDPOINT.format(project=_project_id()),
            headers={"Authorization": f"Bearer {bearer}"},
            json=payload,
            timeout=10,
        )
        if res.status_code == 200:
            return
        # 404 UNREGISTERED / 400 INVALID_ARGUMENT on the token => it is dead.
        detail = res.text or ""
        if res.status_code == 404 or "UNREGISTERED" in detail or (
            res.status_code == 400 and "INVALID_ARGUMENT" in detail
        ):
            _drop_token(conn, token)
        print(f"[push] FCM {res.status_code}: {detail[:200]}")
    except Exception as exc:
        print(f"[push] send failed: {exc}")


def send_to_recipient(conn, *, recipient_type: str, recipient_id: str,
                      title: str, body: str, data: dict | None = None) -> None:
    """Fan a notification out to every device registered for this account.

    Runs on a daemon thread: `_insert()` is called inside the request's DB
    transaction, and a slow FCM round-trip must never delay a coordinator's
    Assign/Close response. Failures are logged and swallowed — a missed push
    must never fail the action that triggered it.
    """
    if not recipient_id or not _project_id():
        return
    try:
        tokens = _tokens_for(conn, recipient_type, str(recipient_id))
    except Exception:
        return  # table missing on an older DB — polling still works
    if not tokens:
        return

    payload = dict(data or {})

    def _run() -> None:
        for tok in tokens:
            _post(conn, tok, title, body, payload)

    threading.Thread(target=_run, daemon=True).start()
