"""
audit.py
--------
Append-only history for a grievance.

`issues` is a "latest value wins" row: every coordinator action overwrites
`coordinator_message`, so the note written at transfer time is destroyed by the
next escalate, and a closed ticket keeps no record of who transferred it or
why. Nothing reconstructed that history — the admin console could only ever
show the last thing that happened.

Every state-changing endpoint now also appends one `issue_events` row. That row
is the only place the following survive:
  • the note the coordinator typed for THAT action,
  • the responsible officer chosen at transfer time,
  • the live photo + voice note the coordinator app captures in its action
    sheets (mandatory before a close),
  • who did it, and when.

Writes here are best-effort by design: an audit failure must never turn a
successful state change into a 500 for the coordinator standing in the street.
"""

from utils import new_id, now_iso, save_upload

# Actions that carry evidence in the coordinator app's action sheets.
EVIDENCE_ACTIONS = ("transfer", "escalate", "close", "mark_false")


async def store_evidence(photo=None, voice=None):
    """Persist the optional photo/voice UploadFiles and return their URLs.

    Both are optional at the API layer: the mobile app enforces "photo + voice
    required to close", but builds already in the field send neither, and
    rejecting those would break every APK already handed out.
    """
    image_url = audio_url = None
    if photo is not None:
        data = await photo.read()
        if data:
            image_url = save_upload(data, photo.filename or "closure.jpg", "image")
    if voice is not None:
        data = await voice.read()
        if data:
            audio_url = save_upload(data, voice.filename or "closure.m4a", "audio")
    return image_url, audio_url


def record(
    conn,
    issue_id: str,
    *,
    action: str,
    actor_type: str,
    actor_id: str = "",
    from_status: str = "",
    to_status: str = "",
    note: str = "",
    department: str = "",
    officer: str = "",
    image_url: str = None,
    audio_url: str = None,
) -> None:
    """Append one immutable row to the grievance's timeline."""
    # Coordinator usernames are matched case-insensitively everywhere else, so
    # normalise them here too. A citizen's user_id is an opaque key — store it
    # exactly as given or a lookup by it stops matching.
    actor = (actor_id or "").strip()
    if actor_type == "coordinator":
        actor = actor.lower()
    try:
        conn.execute(
            """INSERT INTO issue_events (
                   id, issue_id, actor_type, actor_id, action,
                   from_status, to_status, note, department, officer,
                   image_url, audio_url, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                new_id(), issue_id, actor_type, actor,
                action, from_status or "", to_status or "", note or "",
                department or "", officer or "", image_url, audio_url, now_iso(),
            ),
        )
    except Exception as exc:  # pragma: no cover - never break the state change
        print(f"[audit] failed to record {action} on {issue_id}: {exc}")


def timeline(conn, issue_id: str) -> list[dict]:
    """Oldest-first history of everything that happened to a grievance."""
    rows = conn.execute(
        "SELECT * FROM issue_events WHERE issue_id = ? ORDER BY created_at ASC",
        (issue_id,),
    ).fetchall()
    return [dict(r) for r in rows]
