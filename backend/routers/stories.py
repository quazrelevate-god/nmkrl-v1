"""
routers/stories.py
------------------
Ward stories — short-lived photo updates the constituency coordinator posts for
their ward, read by every citizen in that ward.

  GET    /api/stories?ward=58          → active rings for one ward (public)
  POST   /api/coordinator/stories      → post one (coordinator session only)
  DELETE /api/coordinator/stories/{id} → take one down (its author only)

Shape of a ring (one circle in the app's story rail):

    {"title": "Ward 58 Updates", "cover": "/uploads/images/a.jpg",
     "ward": 58, "author": "ravi", "author_name": "Ravi K",
     "updated_at": "...",
     "items": [{"id": "...", "image_url": "...", "caption": "...",
                "created_at": "...", "expires_at": "..."}]}

Stories expire rather than being deleted: the read filters on `expires_at`, so
an expired post is still there for an audit.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile

import corporations
from database import get_db
from session_auth import coordinator_session
from utils import new_id, now_iso, save_upload

public_router = APIRouter(prefix="/api/stories", tags=["stories"])
router = APIRouter(prefix="/api/coordinator/stories", tags=["stories"])

#: How long a story stays on the rail. Instagram's 24 hours — long enough that
#: a morning post is still there for the evening commute, short enough that the
#: rail always reflects what is happening in the ward now.
STORY_TTL_HOURS = 24

#: One upload cap, enforced here rather than trusting the client to compress.
MAX_IMAGE_BYTES = 8 * 1024 * 1024

#: Fallback ring name when the coordinator does not type one.
DEFAULT_TITLE = "Ward Update"

#: Hard ceiling on one read. A ward posting normally produces a handful of
#: stories a day; this exists so a runaway ward (or a scripted client) cannot
#: turn the rail into an unbounded response. Newest are kept.
MAX_ROWS_PER_READ = 200

#: Frames kept per ring, newest last. A ring the app can page through in a
#: minute does not need more, and it bounds the payload per circle too.
MAX_FRAMES_PER_RING = 30


def _rings(rows) -> list[dict]:
    """Group story rows (NEWEST first) into one ring per title.

    Newest-first is what makes the per-ring cap correct: a ring that has run
    past [MAX_FRAMES_PER_RING] drops its OLDEST frames rather than refusing its
    newest, and its cover is the first row it sees. Each ring's items are
    flipped back to oldest-first at the end, which is the order the viewer
    pages through them in.
    """
    by_title: dict[str, dict] = {}
    for r in rows:
        title = (r["title"] or DEFAULT_TITLE).strip() or DEFAULT_TITLE
        ring = by_title.get(title)
        if ring is None:
            # First row of a title is its newest: cover and stamp come free.
            ring = by_title[title] = {
                "title": title,
                "ward": r["ward_no"],
                "author": r["author"],
                "author_name": r["author_name"] or "",
                "cover": r["image_url"],
                "updated_at": r["created_at"],
                "items": [],
            }
        if len(ring["items"]) >= MAX_FRAMES_PER_RING:
            continue
        ring["items"].append(
            {
                "id": r["id"],
                "image_url": r["image_url"],
                "caption": r["caption"] or "",
                "author": r["author"],
                "author_name": r["author_name"] or "",
                "created_at": r["created_at"],
                "expires_at": r["expires_at"],
            }
        )
    for ring in by_title.values():
        ring["items"].reverse()
    # Freshest ring first; the app pins its "Your Story" tile ahead of all.
    return sorted(by_title.values(), key=lambda g: g["updated_at"], reverse=True)


@public_router.get("")
def list_stories(
    ward: int | None = Query(default=None),
    conn=Depends(get_db),
):
    """Active stories for one ward of the LIVE corporation.

    Scoped by corporation, not ward alone: ward numbers are per-corporation, so
    "ward 1" exists in Tambaram and in Chennai and the two must never see each
    other's rail. Every other public read in the app is scoped the same way
    (see routers/issues.py).

    `expires_at` and `now_iso()` are both `datetime.now(timezone.utc)
    .isoformat()`, so they share one fixed-width `+00:00` form and compare
    correctly as TEXT on SQLite and on Postgres alike.

    Ordered NEWEST first in SQL so both caps keep the freshest rows; [_rings]
    flips each ring back to the oldest-first order the viewer pages through.
    """
    now = now_iso()
    corp = corporations.active_id(conn)
    params: list = [corp, now]
    where = "corporation = ? AND expires_at > ?"
    if ward is not None:
        where += " AND ward_no = ?"
        params.append(ward)
    rows = conn.execute(
        f"SELECT * FROM stories WHERE {where} "
        "ORDER BY created_at DESC LIMIT ?",
        (*params, MAX_ROWS_PER_READ),
    ).fetchall()
    return {"rings": _rings(rows)}


def _me(conn, username: str):
    row = conn.execute(
        "SELECT * FROM coordinators WHERE LOWER(username) = ?", (username,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Coordinator not found.")
    return row


@router.post("")
async def post_story(
    title: str = Form(DEFAULT_TITLE),
    caption: str = Form(""),
    ward: str = Form(""),
    image: UploadFile = File(...),
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Post one story to a ward inside the coordinator's own constituency."""
    me = _me(conn, session_username)
    constituency = (me["constituency"] or "").strip()
    corp = corporations.corporation_of_constituency(constituency) or corporations.active_id(conn)

    ward_no = None
    for candidate in (ward, me["home_ward"]):
        try:
            ward_no = int(str(candidate).strip())
            break
        except (TypeError, ValueError):
            continue
    if ward_no is None:
        raise HTTPException(status_code=422, detail="A story needs a ward.")

    # A coordinator may only post into the wards of their own AC — the same
    # boundary every other coordinator write is held to.
    allowed = {str(w) for w in corporations.ac_map(corp).get(constituency, [])}
    if allowed and str(ward_no) not in allowed:
        raise HTTPException(
            status_code=403, detail="That ward is outside your constituency."
        )

    blob = await image.read()
    if not blob:
        raise HTTPException(status_code=422, detail="A story needs a photo.")
    if len(blob) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="That photo is too large.")
    image_url = save_upload(blob, image.filename, "image")

    created = now_iso()
    expires = (
        datetime.now(timezone.utc) + timedelta(hours=STORY_TTL_HOURS)
    ).isoformat()
    story_id = new_id()
    conn.execute(
        "INSERT INTO stories (id, ward_no, corporation, constituency, title, "
        "caption, image_url, author, author_name, created_at, expires_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            story_id,
            ward_no,
            corp,
            constituency,
            (title or DEFAULT_TITLE).strip() or DEFAULT_TITLE,
            (caption or "").strip(),
            image_url,
            session_username,
            me["name"] or "",
            created,
            expires,
        ),
    )
    conn.commit()
    return {
        "id": story_id,
        "ward": ward_no,
        "title": (title or DEFAULT_TITLE).strip() or DEFAULT_TITLE,
        "caption": (caption or "").strip(),
        "image_url": image_url,
        "author": session_username,
        "author_name": me["name"] or "",
        "created_at": created,
        "expires_at": expires,
    }


@router.delete("/{story_id}")
def delete_story(
    story_id: str,
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """Take a story down early. Only the coordinator who posted it may."""
    row = conn.execute("SELECT * FROM stories WHERE id = ?", (story_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Story not found.")
    if (row["author"] or "").lower() != session_username:
        raise HTTPException(status_code=403, detail="That is not your story.")
    conn.execute("DELETE FROM stories WHERE id = ?", (story_id,))
    conn.commit()
    return {"ok": True}
