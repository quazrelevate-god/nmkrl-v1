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
# UPLOAD_DIR resolution mirrors DB_PATH: env override → mounted /data volume
# (Railway, auto-detected) → local folder (development default).
UPLOAD_DIR = (
    os.environ.get("UPLOAD_DIR")
    or ("/data/uploads" if os.path.isdir("/data") else None)
    or os.path.join(BASE_DIR, "uploads")
)
IMAGE_DIR = os.path.join(UPLOAD_DIR, "images")
AUDIO_DIR = os.path.join(UPLOAD_DIR, "audio")
DOC_DIR = os.path.join(UPLOAD_DIR, "documents")

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


def ticket_number(issue_id: str) -> str:
    """Human-friendly tracking id derived from the issue UUID — FMS-XXXXXXXX
    (first 8 hex chars, upper-cased). Matches lib/ticket.js + ticket.dart so
    the derived and stored values are identical. Generated once at insert and
    persisted so every surface fetches the SAME value from the DB."""
    if not issue_id:
        return "FMS-UNKNOWN"
    hex8 = issue_id.replace("-", "")[:8].upper()
    return f"FMS-{hex8}"


def ensure_upload_dirs() -> None:
    """Create upload folders if missing."""
    os.makedirs(IMAGE_DIR, exist_ok=True)
    os.makedirs(AUDIO_DIR, exist_ok=True)
    os.makedirs(DOC_DIR, exist_ok=True)


def save_upload(file_bytes: bytes, original_name: str, kind: str) -> str:
    """
    Persist an uploaded blob to disk and return its public URL path
    (e.g. ``/uploads/images/<uuid>.jpg``) for storage in the DB.

    ``kind`` is "image", "audio" or "document".
    """
    ensure_upload_dirs()
    _defaults = {"image": ".jpg", "audio": ".webm", "document": ".pdf"}
    _dirs = {"image": IMAGE_DIR, "audio": AUDIO_DIR, "document": DOC_DIR}
    _subdirs = {"image": "images", "audio": "audio", "document": "documents"}
    ext = os.path.splitext(original_name or "")[1] or _defaults.get(kind, ".bin")
    fname = f"{new_id()}{ext}"
    path = os.path.join(_dirs.get(kind, IMAGE_DIR), fname)
    with open(path, "wb") as fh:
        fh.write(file_bytes)
    return f"/uploads/{_subdirs.get(kind, 'images')}/{fname}"


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


# ── Assembly Constituency (MLA) mapping ──────────────────────────────────────
# Maps each Chennai Assembly Constituency to the GCC ward numbers it covers.
# Some wards clip/overlap across constituency boundaries, so a single ward can
# belong to more than one AC — the lookup therefore returns a list.
CHENNAI_AC_MAP = {
    "11 - Dr. Radhakrishnan Nagar": ["38", "39", "40", "41", "42", "43", "47"],
    "12 - Perambur": ["34", "35", "36", "37", "44", "45", "46", "64", "65", "66", "67", "68", "69", "70"],
    "13 - Kolathur": ["64", "65", "66", "67", "68", "69", "70"],  # Shared/Overlapping clusters
    "14 - Villivakkam": ["94", "95", "96", "97", "98", "102", "103", "104"],
    "15 - Thiru-Vi-Ka-Nagar": ["71", "72", "73", "74", "75", "76"],
    "16 - Egmore": ["58", "61", "77", "78", "104", "108"],
    "17 - Harbour": ["54", "55", "56", "57", "59", "60"],
    "18 - Chepauk-Thiruvallikeni": ["62", "63", "114", "115", "116", "119", "120"],
    "19 - Thousand Lights": ["109", "110", "111", "112", "113", "117", "118"],
    "20 - Anna Nagar": ["100", "101", "102", "103", "105", "106", "107"],
    "21 - Virugambakkam": ["127", "128", "129", "136", "137", "138"],
    "22 - Saidapet": ["126", "139", "140", "142", "168", "169", "170", "171", "172", "173", "174", "175", "176", "177", "178", "179", "180"],
    "23 - Thiyagarayanagar": ["130", "131", "132", "133", "134", "135", "141"],
    "24 - Mylapore": ["126", "170", "171", "172", "173", "174", "175", "176", "177", "178", "179", "180"],
    "25 - Velachery": ["139", "140", "142", "168", "169", "181", "182", "183", "184", "192", "193", "194"],
    "26 - Shozhinganallur": ["191", "195", "196", "197", "198", "199", "200"],
}


def get_constituency_by_ward(ward_no) -> list:
    """Return the list of Assembly Constituencies a ward falls in.

    Wards can clip/overlap across AC lines, so this returns every matching AC
    name (empty list if the ward maps to none).
    """
    if ward_no is None:
        return []
    key = str(ward_no).strip()
    return [ac for ac, wards in CHENNAI_AC_MAP.items() if key in wards]


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
    # Always surface a ticket number — use the stored one, else derive (keeps
    # legacy rows consistent with the deterministic FMS-XXXXXXXX scheme).
    if not data.get("ticket_number"):
        data["ticket_number"] = ticket_number(data.get("id", ""))
    # Derive the Assembly Constituency (MLA) from the ward so admin AC views
    # can group/filter grievances. Wards can span ACs, so expose both the full
    # list and a single primary value for convenience.
    acs = get_constituency_by_ward(data.get("ward_no"))
    data["constituencies"] = acs
    data["constituency"] = acs[0] if acs else None
    return data
