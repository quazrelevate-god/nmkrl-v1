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

from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/api/departments", tags=["departments"])

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


@router.get("/tree")
def tree():
    """Return the whole {departments: {...}} tree."""
    data = _load()
    depts = data.get("departments", {})
    return {"count": len(depts), "departments": depts}
