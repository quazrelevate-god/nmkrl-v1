"""
routers/departments.py
----------------------
Serves the Tamil Nadu grievance-routing taxonomy (39 Government Departments →
Grievance Type → Sub-Type → Sub-Department + Responsible Officers). The
mobile coordinator's Dept Transfer sheet fetches this once at open and picks
a route from it — mirroring the web admin's `/admin/routing` behaviour.

The taxonomy is a static JSON blob at ``backend/data/departments.json``,
identical to the copy the web app ships as ``frontend/public/departments.json``.
"""

import json
import os

from fastapi import APIRouter, Depends, HTTPException, Query

from database import get_db
from utils import now_iso

router = APIRouter(prefix="/api/departments", tags=["departments"])

# Demo desk numbers for the responsible officers. The taxonomy names 600
# officer SLOTS (designations, not people), and no real directory exists yet —
# these four lines stand in so the coordinator's WhatsApp dispatch has a real
# chat to open instead of dumping the message into a contact picker. Admin can
# overwrite any of them in Departmental Configuration; the seeder never
# overwrites a number that is already set.
DEMO_OFFICER_NUMBERS = [
    "9003259339",
    "9840247628",
    "9840763977",
    "9710225175",
]


def contact_key(dept: str, sub_dept: str, officer: str) -> str:
    """Mirrors frontend/lib/deptRouting.js contactKey() exactly."""
    return f"{dept}||{sub_dept}||{officer}"

_TAXONOMY_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "data", "departments.json",
)

_cached: dict | None = None


def _load() -> dict:
    global _cached
    if _cached is None:
        try:
            with open(_TAXONOMY_PATH, "r", encoding="utf-8") as f:
                _cached = json.load(f)
        except FileNotFoundError:
            _cached = {"departments": {}}
    return _cached


def _officer_slots() -> list[tuple[str, str, str]]:
    """Every (department, sub-department, officer) the taxonomy defines."""
    slots = set()
    for dept, types in _load().get("departments", {}).items():
        for subtypes in types.values():
            for node in subtypes.values():
                for sd in node.get("sd", []):
                    for ro in node.get("ro", []):
                        slots.add((dept, sd, ro))
    return sorted(slots)


def seed_officer_numbers(conn) -> None:
    """Give every officer slot a working desk number, once.

    The coordinator's Dept Transfer opens a WhatsApp chat with the responsible
    officer, which needs an actual number — without one the app could only open
    WhatsApp and hope the coordinator picked the right contact.

    The number is chosen by hashing the contact key, so it is spread across the
    demo lines but STABLE: the same officer keeps the same number across
    restarts and redeploys instead of being reshuffled under the admin's feet.
    Rows that already carry a number are never touched, so anything typed in
    Departmental Configuration wins.
    """
    import zlib

    existing = {
        r["contact_key"]
        for r in conn.execute(
            "SELECT contact_key FROM dept_officers WHERE mobile <> ''"
        ).fetchall()
    }
    added = 0
    for dept, sd, ro in _officer_slots():
        key = contact_key(dept, sd, ro)
        if key in existing:
            continue
        mobile = DEMO_OFFICER_NUMBERS[
            zlib.crc32(key.encode("utf-8")) % len(DEMO_OFFICER_NUMBERS)
        ]
        conn.execute(
            """INSERT INTO dept_officers (contact_key, name, mobile, updated_at)
               VALUES (?, '', ?, ?)
               ON CONFLICT(contact_key) DO UPDATE SET
                   mobile = excluded.mobile, updated_at = excluded.updated_at
                 WHERE dept_officers.mobile = ''""",
            (key, mobile, now_iso()),
        )
        added += 1
    if added:
        print(f"[seed] officer desk numbers assigned to {added} slots")


@router.get("/tree")
def tree():
    """Return the whole {departments: {...}} tree."""
    data = _load()
    depts = data.get("departments", {})
    return {"count": len(depts), "departments": depts}


@router.get("/officer")
def officer_contact(
    dept: str = Query(...),
    sub_dept: str = Query(""),
    officer: str = Query(...),
    conn=Depends(get_db),
):
    """The configured contact for one responsible-officer slot.

    The coordinator app calls this when its routing panel resolves, so the
    WhatsApp dispatch can open that officer's chat directly. A single lookup
    rather than the whole 600-row contact book, because the phone only ever
    needs the one it is about to message.

    Falls back to any contact configured for the same officer in the same
    department when the sub-department does not match exactly — the routing
    tree can reach one designation through more than one sub-department.
    """
    row = conn.execute(
        "SELECT name, mobile FROM dept_officers WHERE contact_key = ?",
        (contact_key(dept, sub_dept, officer),),
    ).fetchone()
    if row is None or not (row["mobile"] or "").strip():
        row = conn.execute(
            """SELECT name, mobile FROM dept_officers
                WHERE contact_key LIKE ? AND contact_key LIKE ? AND mobile <> ''
                LIMIT 1""",
            (f"{dept}||%", f"%||{officer}"),
        ).fetchone()
    return {
        "dept": dept,
        "sub_dept": sub_dept,
        "officer": officer,
        "name": (row["name"] if row else "") or "",
        "mobile": (row["mobile"] if row else "") or "",
    }
