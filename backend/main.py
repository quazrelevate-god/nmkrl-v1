"""
main.py
-------
FastAPI entrypoint for FixMyStreet India.

Responsibilities:
  * Configure CORS so the Next.js dev server (localhost:3000) can call the API.
  * Mount the /uploads static directory for serving stored images/audio.
  * Initialize the SQLite schema on startup.
  * Wire up the issues and admin routers.

Run with:
    uvicorn main:app --reload --port 8000
"""

import os
import shutil
import sqlite3
import time
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import boundaries
from admin_auth import issue_token, require_admin, verify_credentials
from database import DB_PATH, get_connection, init_db
from gemini_service import keyword_department
from routers import (
    admin, auth, coordinator, coordinators_admin, departments, issues,
    notifications, servicehub,
)
from utils import (
    UPLOAD_DIR,
    ensure_upload_dirs,
    get_constituency_by_ward,
    new_id,
    now_iso,
    ticket_number,
)

SEED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "seed")

load_dotenv()


def _backfill_zones_and_departments() -> None:
    """One-time backfill of real zone/ward + department for pre-existing rows.

    Zone/ward come from the KML point-in-polygon lookup. Departments use the
    offline keyword classifier here to avoid LLM calls on startup; new
    submissions route via Gemini at report time.
    """
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT id, title, transcript, latitude, longitude, ward_no, "
            "zone, department, ticket_number FROM issues"
        ).fetchall()
        for r in rows:
            updates, params = [], []
            # Recompute when unset, or when zone is a legacy roman numeral
            # (pre-integer-migration rows) rather than the new plain integer.
            zone_val = r["zone"]
            if r["ward_no"] is None or not zone_val or not str(zone_val).isdigit():
                loc = boundaries.locate(r["latitude"], r["longitude"])
                ward = int(loc["ward"]) if loc["ward"] is not None else None
                updates += ["ward_no = ?", "zone = ?", "zone_name = ?"]
                params += [ward, loc["zone"], loc["zone_name"]]
            if not r["department"]:
                updates.append("department = ?")
                params.append(keyword_department(f"{r['title']} {r['transcript'] or ''}"))
            # Backfill the stored ticket number for pre-existing rows.
            if not r["ticket_number"]:
                updates.append("ticket_number = ?")
                params.append(ticket_number(r["id"]))
            if updates:
                params.append(r["id"])
                conn.execute(
                    f"UPDATE issues SET {', '.join(updates)} WHERE id = ?", params
                )


def _db_is_empty() -> bool:
    """True ONLY when the target DB genuinely holds no grievances.

    A read failure is not emptiness. This used to `return True` on any
    sqlite3.Error, which made "I could not read the database" indistinguishable
    from "the database is new" — and the caller's response to empty is to copy
    the demo seed over the file. A restart that raced an in-flight write, or a
    volume still settling, was therefore enough to silently destroy every live
    grievance, coordinator and assignment and replace them with demo data.
    Observed in testing: a 1,037-grievance database wiped back to the 1,020-row
    seed because a `kill -9` had left the file locked for a moment.

    Only "no such table" actually proves a fresh file. Everything else means we
    could not tell, and the safe answer to "should I overwrite live data?" when
    the answer is unknown is no.
    """
    if not os.path.exists(DB_PATH):
        return True
    try:
        # Wait out a transient lock rather than treating it as an answer.
        conn = sqlite3.connect(DB_PATH, timeout=15)
        try:
            n = conn.execute("SELECT COUNT(*) FROM issues").fetchone()[0]
        finally:
            conn.close()
        return n == 0
    except sqlite3.Error as exc:
        if "no such table" in str(exc).lower():
            return True  # schema not created yet — a genuinely fresh file
        print(f"[seed] NOT seeding: cannot read {DB_PATH} ({exc}). "
              f"Refusing to overwrite a database whose contents are unknown.")
        return False


def _seed_if_needed() -> None:
    """Self-heal a fresh/empty persistent volume from the bundled seed.

    On the first boot against an empty volume (or a brand-new container) the
    demo DB + uploaded media are copied into place BEFORE requests are served,
    so the presentation data is always present. It never overwrites live data:
    the DB is only seeded when empty, and each media file is copied only if it
    isn't already there.
    """
    print(f"[seed] DB_PATH={DB_PATH} UPLOAD_DIR={UPLOAD_DIR} /data mounted={os.path.isdir('/data')}")
    seed_db = os.path.join(SEED_DIR, "fixmystreet.db")
    # FORCE_RESEED=1 resets the demo data on the next boot, on purpose.
    #
    # The volume at /data persists across redeploys — that is what it is for —
    # so the automatic seed only ever fires on a genuinely fresh volume. If you
    # DO want a clean demo dataset before a pitch, set this, redeploy, then
    # unset it. Doing it deliberately is the point: the old behaviour reseeded
    # whenever the database merely failed to read, which is how live data gets
    # destroyed by a restart nobody thought was dangerous.
    forced = os.environ.get("FORCE_RESEED", "").strip().lower() in ("1", "true", "yes")
    if forced:
        print("[seed] FORCE_RESEED set — resetting to the bundled demo data.")
    if os.path.exists(seed_db) and (forced or _db_is_empty()):
        os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
        # _db_is_empty() should already have ruled this out, but seeding is
        # destructive and unrecoverable — keep a copy of anything non-trivial
        # that was there, so a wrong answer costs a file rename, not the data.
        if os.path.exists(DB_PATH) and os.path.getsize(DB_PATH) > 4096:
            backup = f"{DB_PATH}.pre-seed-{int(time.time())}"
            shutil.copy2(DB_PATH, backup)
            print(f"[seed] Existing DB backed up → {backup}")
        shutil.copy2(seed_db, DB_PATH)
        print(f"[seed] Seeded demo DB → {DB_PATH}")

    seed_uploads = os.path.join(SEED_DIR, "uploads")
    if os.path.isdir(seed_uploads):
        copied = 0
        for sub in ("images", "audio"):
            src = os.path.join(seed_uploads, sub)
            dst = os.path.join(UPLOAD_DIR, sub)
            if not os.path.isdir(src):
                continue
            os.makedirs(dst, exist_ok=True)
            for name in os.listdir(src):
                if name == ".gitkeep":
                    continue
                dst_file = os.path.join(dst, name)
                if not os.path.exists(dst_file):
                    shutil.copy2(os.path.join(src, name), dst_file)
                    copied += 1
        if copied:
            print(f"[seed] Restored {copied} media file(s) → {UPLOAD_DIR}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialise DB + upload dirs, and parse the GCC boundary KMLs once."""
    _seed_if_needed()  # populate a fresh volume with the bundled demo data
    ensure_upload_dirs()
    init_db()
    # Parse zones.kml + wards.kml into in-memory shapely polygons exactly once.
    boundaries.load_boundaries()
    _backfill_zones_and_departments()
    # Give every responsible-officer slot a desk number so the coordinator's
    # WhatsApp dispatch has a chat to open. Idempotent; never overwrites a
    # number configured in the admin console.
    from routers.departments import seed_officer_numbers
    with get_connection() as conn:
        seed_officer_numbers(conn)
    yield


app = FastAPI(
    title="FixMyStreet India API",
    version="1.0.0",
    description="Civic grievance reporting backend (PoC).",
    lifespan=lifespan,
)

# CORS: allow the local Next.js front-end (and any origin during the PoC).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve uploaded media at /uploads/...
ensure_upload_dirs()
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

# Routers
app.include_router(auth.router)
app.include_router(issues.router)
# The admin surface is the only place accounts are created and passwords are
# reset, so it is gated as a whole rather than endpoint by endpoint — a route
# added later is protected by default instead of by remembering to say so.
app.include_router(admin.router, dependencies=[Depends(require_admin)])
app.include_router(coordinator.router)
app.include_router(coordinators_admin.router, dependencies=[Depends(require_admin)])


@app.post("/api/admin/auth/login", tags=["admin"])
def admin_login(username: str = Form(...), password: str = Form(...)):
    """Sign in to the admin console. Deliberately NOT behind require_admin."""
    if not verify_credentials(username, password):
        raise HTTPException(status_code=401, detail="Invalid username or password.")
    return issue_token(username.strip().lower())


@app.get("/api/admin/auth/me", tags=["admin"])
def admin_me(who: str = Depends(require_admin)):
    """Cheap token check so the console can validate a stored token on load."""
    return {"username": who}


app.include_router(departments.router)
app.include_router(notifications.router)
app.include_router(servicehub.router)


@app.get("/")
def root():
    """Health/info endpoint."""
    return {
        "name": "FixMyStreet India API",
        "status": "ok",
        "gemini_configured": bool(
            os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
        ),
        "docs": "/docs",
    }


@app.get("/api/boundaries")
def get_boundaries():
    """Real GCC zone + ward polygons as GeoJSON FeatureCollections (for the map)."""
    return boundaries.geojson()


class LocateRequest(BaseModel):
    latitude: float
    longitude: float


@app.post("/api/locate")
def locate_coordinates(body: LocateRequest):
    """Resolve a coordinate to its real GCC zone + ward via point-in-polygon.

    Runs the coordinate through the in-memory KML boundary polygons, logs the
    lookup to ``location_logs``, and returns the detected zone/ward. Fields are
    null when the point falls outside Greater Chennai Corporation limits.
    """
    result = boundaries.locate(body.latitude, body.longitude)

    # Map the detected ward → its Assembly Constituency/-ies (may overlap).
    constituencies = get_constituency_by_ward(result["ward"])
    primary_ac = constituencies[0] if constituencies else None

    with get_connection() as conn:
        conn.execute(
            "INSERT INTO location_logs "
            "(id, latitude, longitude, detected_zone, detected_zone_name, "
            " detected_ward, assembly_constituency, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                new_id(),
                body.latitude,
                body.longitude,
                result["zone"],
                result["zone_name"],
                result["ward"],
                primary_ac,
                now_iso(),
            ),
        )

    return {
        "latitude": body.latitude,
        "longitude": body.longitude,
        "zone": result["zone"],
        "zone_name": result["zone_name"],
        "region": result["region"],
        "ward": result["ward"],
        "detected_constituencies": constituencies,
        "inside": result["inside"],
    }


@app.get("/api/health")
def health():
    return {"status": "healthy", "boundaries": boundaries.summary()}
