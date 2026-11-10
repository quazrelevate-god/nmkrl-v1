"""
routers/stories.py
------------------
Ward stories — short-lived photo updates the constituency coordinator posts for
their ward, read by every citizen in that ward.

A post is NOT public when it is made. A coordinator writes in the MLA
office's name to everyone in a ward, so the office reviews it first: a new
story lands as PENDING and only an APPROVED one is ever served to citizens.

  GET    /api/stories?ward=58          → approved rings for one ward (public)
  POST   /api/coordinator/stories      → post one, PENDING (coordinator)
  GET    /api/coordinator/stories/mine → own posts and their review state
  DELETE /api/coordinator/stories/{id} → take one down (its author only)

  GET    /api/admin/stories            → the office's review queue
  POST   /api/admin/stories/{id}/approve
  POST   /api/admin/stories/{id}/reject
  POST   /api/admin/stories/{id}/revert  → undo a REJECTION, never a publish

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
from admin_auth import require_admin
from database import get_db
from routers.notifications import emit_story_review
from session_auth import coordinator_session
from tenancy import current_tenant
from utils import new_id, now_iso, save_upload

public_router = APIRouter(prefix="/api/stories", tags=["stories"])
router = APIRouter(prefix="/api/coordinator/stories", tags=["stories"])
admin_router = APIRouter(prefix="/api/admin/stories", tags=["stories"])

#: Review states. A story is PENDING from the moment it is posted; the MLA
#: office moves it to one of the other two and it never moves again.
PENDING = "PENDING"
APPROVED = "APPROVED"
REJECTED = "REJECTED"

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
    """APPROVED, unexpired stories for one ward of the LIVE corporation.

    The approval filter is the whole point of the review flow and it lives
    HERE, on the only read citizens can reach — not in the app, which could be
    an old build, and not on the write, which cannot know what a reviewer will
    decide later. A pending or rejected story is simply not in this result.

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
    params: list = [corp, APPROVED, now]
    where = "corporation = ? AND status = ? AND expires_at > ?"
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
    # PENDING, always. There is no path that posts straight to a ward — the
    # status is set here rather than taken from the request, so a crafted
    # client cannot publish itself.
    conn.execute(
        "INSERT INTO stories (id, ward_no, corporation, constituency, title, "
        "caption, image_url, author, author_name, created_at, expires_at, "
        "status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
            PENDING,
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
        "status": PENDING,
    }


def _serialize(row) -> dict:
    """One story with its review state, for the coordinator and the office."""
    return {
        "id": row["id"],
        "ward": row["ward_no"],
        "title": row["title"],
        "caption": row["caption"] or "",
        "image_url": row["image_url"],
        "author": row["author"],
        "author_name": row["author_name"] or "",
        "created_at": row["created_at"],
        "expires_at": row["expires_at"],
        "status": row["status"] or PENDING,
        "reviewed_by": row["reviewed_by"] or "",
        "reviewed_at": row["reviewed_at"] or "",
        "review_note": row["review_note"] or "",
    }


@router.get("/mine")
def my_stories(
    session_username: str = Depends(coordinator_session),
    conn=Depends(get_db),
):
    """The coordinator's own posts, whatever state they are in.

    Without this a coordinator posts into silence: their story is not on the
    rail (it is not approved yet) and nothing tells them why. This is the only
    read that returns PENDING and REJECTED rows, and only ever the caller's
    own.
    """
    rows = conn.execute(
        "SELECT * FROM stories WHERE author = ? "
        "ORDER BY created_at DESC LIMIT ?",
        (session_username, MAX_ROWS_PER_READ),
    ).fetchall()
    return {"stories": [_serialize(r) for r in rows]}


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


# ── The MLA office's review queue ─────────────────────────────────────────
#
# Mounted under /api/admin, so it inherits the admin token guard and the
# tenant dependency the rest of the console uses. Every query here is scoped
# to the signed-in office's own wards and corporation: one office must never
# see, let alone approve, another constituency's posts.


def _office_scope(tenant: dict) -> tuple[str, list]:
    """SQL fragment limiting stories to this office's wards."""
    wards = tenant["wards"]
    placeholders = ",".join("?" for _ in wards)
    return (
        f"(corporation = ? AND CAST(ward_no AS TEXT) IN ({placeholders}))",
        [tenant["corporation"], *wards],
    )


def _load_for_office(conn, story_id: str, tenant: dict):
    scope, params = _office_scope(tenant)
    row = conn.execute(
        f"SELECT * FROM stories WHERE id = ? AND {scope}", (story_id, *params)
    ).fetchone()
    if row is None:
        # Deliberately the same answer whether the story does not exist or
        # belongs to another office: a 403 here would confirm that an id is
        # real to someone with no business knowing.
        raise HTTPException(status_code=404, detail="Story not found.")
    return row


@admin_router.get("")
def review_queue(
    status: str = Query(default=PENDING),
    ward: int | None = Query(default=None),
    conn=Depends(get_db),
    tenant: dict = Depends(current_tenant),
    _admin: str = Depends(require_admin),
):
    """Stories awaiting review, or those already decided.

    Defaults to PENDING — the queue. `status=ALL` returns every state, which
    is what the console's history view wants.

    Expired stories are INCLUDED. A post that sat unreviewed past its 24 hours
    still has to be closed out, and hiding it would leave the queue quietly
    wrong; the serialized row carries `expires_at` so the console can mark it
    as lapsed.
    """
    scope, params = _office_scope(tenant)
    where = scope
    if status and status.upper() != "ALL":
        where += " AND status = ?"
        params.append(status.upper())
    if ward is not None:
        where += " AND ward_no = ?"
        params.append(ward)
    rows = conn.execute(
        f"SELECT * FROM stories WHERE {where} "
        "ORDER BY created_at ASC LIMIT ?",
        (*params, MAX_ROWS_PER_READ),
    ).fetchall()
    pending = conn.execute(
        f"SELECT COUNT(*) FROM stories WHERE {scope} AND status = ?",
        (*_office_scope(tenant)[1], PENDING),
    ).fetchone()
    return {
        "stories": [_serialize(r) for r in rows],
        # The badge count for the console's nav, so it does not have to fetch
        # the whole queue to know whether anything is waiting.
        "pending": pending[0] if pending else 0,
    }


def _decide(conn, story_id: str, tenant: dict, admin: str, status: str,
            note: str) -> dict:
    row = _load_for_office(conn, story_id, tenant)
    current = row["status"] or PENDING
    if current != PENDING:
        # Reviews are one-way. Letting an approved story be un-approved would
        # mean a post could vanish from a ward's rail hours after people saw
        # it; taking one down is what DELETE is for, and it leaves a trace.
        raise HTTPException(
            status_code=409,
            detail=f"That story has already been {current.lower()}.",
        )
    conn.execute(
        "UPDATE stories SET status = ?, reviewed_by = ?, reviewed_at = ?, "
        "review_note = ? WHERE id = ?",
        (status, admin, now_iso(), (note or "").strip(), story_id),
    )
    decided = _load_for_office(conn, story_id, tenant)
    # Tell the coordinator, and in doing so refresh their rail: both home
    # screens reload stories on any notification, so an approval reaches the
    # ward without anyone reopening the app. Emitted before the commit so the
    # decision and its notification land together or not at all.
    emit_story_review(conn, decided, status, (note or "").strip())
    conn.commit()
    return _serialize(decided)


@admin_router.post("/{story_id}/approve")
def approve_story(
    story_id: str,
    note: str = Form(""),
    conn=Depends(get_db),
    tenant: dict = Depends(current_tenant),
    admin: str = Depends(require_admin),
):
    """Publish it. From here it is on the ward's rail until it expires."""
    return _decide(conn, story_id, tenant, admin, APPROVED, note)


@admin_router.post("/{story_id}/reject")
def reject_story(
    story_id: str,
    note: str = Form(""),
    conn=Depends(get_db),
    tenant: dict = Depends(current_tenant),
    admin: str = Depends(require_admin),
):
    """Turn it down. The row stays, so the coordinator can see the reason."""
    return _decide(conn, story_id, tenant, admin, REJECTED, note)


@admin_router.post("/{story_id}/revert")
def revert_story(
    story_id: str,
    conn=Depends(get_db),
    tenant: dict = Depends(current_tenant),
    admin: str = Depends(require_admin),
):
    """Put a REJECTED story back in the queue — the console's Undo.

    Rejected only, and that asymmetry is the point. A rejection was never
    public, so undoing one costs nothing. An approval may already be on a
    ward's rail and in front of citizens; pulling it back would make a post
    they have seen vanish with no trace, which is what DELETE is for. So
    approve stays final and reject does not.
    """
    row = _load_for_office(conn, story_id, tenant)
    current = row["status"] or PENDING
    if current == PENDING:
        return _serialize(row)
    if current == APPROVED:
        raise HTTPException(
            status_code=409,
            detail="That story is already published. Delete it instead.",
        )
    conn.execute(
        "UPDATE stories SET status = ?, reviewed_by = NULL, reviewed_at = NULL, "
        "review_note = '' WHERE id = ?",
        (PENDING, story_id),
    )
    conn.commit()
    return _serialize(_load_for_office(conn, story_id, tenant))
