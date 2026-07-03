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
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import boundaries
from database import get_connection, init_db
from gemini_service import keyword_department
from routers import admin, issues
from utils import UPLOAD_DIR, ensure_upload_dirs, new_id, now_iso

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
            "zone, department FROM issues"
        ).fetchall()
        for r in rows:
            updates, params = [], []
            if r["ward_no"] is None or not r["zone"]:
                loc = boundaries.locate(r["latitude"], r["longitude"])
                ward = int(loc["ward"]) if loc["ward"] is not None else None
                updates += ["ward_no = ?", "zone = ?", "zone_name = ?"]
                params += [ward, loc["zone"], loc["zone_name"]]
            if not r["department"]:
                updates.append("department = ?")
                params.append(keyword_department(f"{r['title']} {r['transcript'] or ''}"))
            if updates:
                params.append(r["id"])
                conn.execute(
                    f"UPDATE issues SET {', '.join(updates)} WHERE id = ?", params
                )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialise DB + upload dirs, and parse the GCC boundary KMLs once."""
    ensure_upload_dirs()
    init_db()
    # Parse zones.kml + wards.kml into in-memory shapely polygons exactly once.
    boundaries.load_boundaries()
    _backfill_zones_and_departments()
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
app.include_router(issues.router)
app.include_router(admin.router)


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

    with get_connection() as conn:
        conn.execute(
            "INSERT INTO location_logs "
            "(id, latitude, longitude, detected_zone, detected_zone_name, "
            " detected_ward, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                new_id(),
                body.latitude,
                body.longitude,
                result["zone"],
                result["zone_name"],
                result["ward"],
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
        "inside": result["inside"],
    }


@app.get("/api/health")
def health():
    return {"status": "healthy", "boundaries": boundaries.summary()}
