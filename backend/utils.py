"""
utils.py
--------
Shared helpers: Haversine distance, ID/time generation, row serialization,
and file persistence for uploaded image/audio blobs.
"""

import json
import os
import sys
import urllib.request
import uuid
from datetime import datetime, timezone
from math import asin, cos, radians, sin, sqrt

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
IMAGE_DIR = os.path.join(UPLOAD_DIR, "images")
AUDIO_DIR = os.path.join(UPLOAD_DIR, "audio")

# Earth's mean radius in meters.
EARTH_RADIUS_M = 6_371_000


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Great-circle distance between two (lat, lng) points in METERS.

    Used for the 50-meter duplicate check and the nearby-radius query.
    """
    rlat1, rlon1, rlat2, rlon2 = map(radians, (lat1, lon1, lat2, lon2))
    dlat = rlat2 - rlat1
    dlon = rlon2 - rlon1
    a = sin(dlat / 2) ** 2 + cos(rlat1) * cos(rlat2) * sin(dlon / 2) ** 2
    c = 2 * asin(sqrt(a))
    return EARTH_RADIUS_M * c


def new_id() -> str:
    """Return a fresh UUID4 string."""
    return str(uuid.uuid4())


def now_iso() -> str:
    """Current UTC timestamp as ISO-8601 string."""
    return datetime.now(timezone.utc).isoformat()


def ensure_upload_dirs() -> None:
    """Create upload folders if missing."""
    os.makedirs(IMAGE_DIR, exist_ok=True)
    os.makedirs(AUDIO_DIR, exist_ok=True)


def save_upload(file_bytes: bytes, original_name: str, kind: str) -> str:
    """
    Persist an uploaded blob to disk and return its public URL path
    (e.g. ``/uploads/images/<uuid>.jpg``) for storage in the DB.

    ``kind`` is either "image" or "audio".
    """
    ensure_upload_dirs()
    ext = os.path.splitext(original_name or "")[1] or (".jpg" if kind == "image" else ".webm")
    fname = f"{new_id()}{ext}"
    target_dir = IMAGE_DIR if kind == "image" else AUDIO_DIR
    path = os.path.join(target_dir, fname)
    with open(path, "wb") as fh:
        fh.write(file_bytes)
    subdir = "images" if kind == "image" else "audio"
    return f"/uploads/{subdir}/{fname}"


_NOMINATIM_UA = "FixMyStreetIndia/1.0 (civic grievance PoC; contact: admin@fixmystreet.in)"


def reverse_geocode(lat: float, lng: float) -> str:
    """
    Return a human-readable area name for the given coordinates via the
    OpenStreetMap Nominatim API. Fallback order: suburb → neighbourhood → city.
    Returns an empty string on any failure so the caller never crashes.
    """
    url = (
        f"https://nominatim.openstreetmap.org/reverse"
        f"?lat={lat}&lon={lng}&format=json&zoom=16"
    )
    req = urllib.request.Request(url, headers={"User-Agent": _NOMINATIM_UA})
    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            data = json.loads(res.read().decode())
        addr = data.get("address", {})
        area = (
            addr.get("suburb")
            or addr.get("neighbourhood")
            or addr.get("city_district")
            or addr.get("city")
            or addr.get("town")
            or addr.get("village")
            or ""
        )
        print(f"[geocode] ({lat},{lng}) → {area!r}", file=sys.stderr)
        return area
    except Exception as exc:
        print(f"[geocode] failed for ({lat},{lng}): {exc}", file=sys.stderr)
        return ""


def serialize_issue(row) -> dict:
    """
    Convert a sqlite Row for the issues table into a JSON-friendly dict,
    decoding the ``summary_highlights`` JSON column into a real list.
    """
    if row is None:
        return None
    data = dict(row)
    raw = data.get("summary_highlights")
    try:
        data["summary_highlights"] = json.loads(raw) if raw else []
    except (TypeError, ValueError):
        data["summary_highlights"] = []
    data["notify_reporter"] = bool(data.get("notify_reporter", 0))
    return data
