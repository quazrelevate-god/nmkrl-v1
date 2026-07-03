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

from database import get_connection, init_db
from gemini_service import keyword_department
from routers import admin, issues
from utils import UPLOAD_DIR, ensure_upload_dirs
from wards import WARDS, ward_for_coords

load_dotenv()


def _backfill_wards_and_departments() -> None:
    """One-time backfill of ward_no/department for pre-existing rows.

    Wards are deterministic (no LLM). Departments use the offline keyword
    classifier here to avoid LLM calls on startup; new submissions route via
    Gemini at report time.
    """
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT id, title, transcript, latitude, longitude, ward_no, department "
            "FROM issues"
        ).fetchall()
        for r in rows:
            updates, params = [], []
            if r["ward_no"] is None:
                updates.append("ward_no = ?")
                params.append(ward_for_coords(r["latitude"], r["longitude"]))
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
    """Initialise DB + upload dirs before serving requests."""
    ensure_upload_dirs()
    init_db()
    _backfill_wards_and_departments()
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


@app.get("/api/wards")
def list_wards():
    """The 200-block Chennai ward grid (single source of truth for the maps)."""
    return {"count": len(WARDS), "wards": WARDS}


@app.get("/api/health")
def health():
    return {"status": "healthy"}
