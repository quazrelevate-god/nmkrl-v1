"""
corporations.py
---------------
The municipal corporations the app can serve, and which one is live.

The app began as Greater Chennai Corporation only; the pilot now runs in the
Tambaram City Municipal Corporation. Both stay in the codebase with all their
data, and the MLA-office console switches between them. Exactly one is ACTIVE
at a time: it decides the map, the wards and constituencies the apps offer,
where a new grievance may be filed, and which office the console signs in to.

Ward numbers repeat across corporations (both have a ward 58), so a grievance
records the corporation it was filed in (issues.corporation) and every ward
lookup is made within one corporation.

The active corporation lives in the app_settings table, so switching it needs
no redeploy and every worker sees the same value.
"""

from __future__ import annotations

import os

from database import get_connection
from utils import CHENNAI_AC_MAP

# Tambaram's ward -> assembly constituency list is not on the corporation's ward
# map, and a guess would misfile grievances between two MLAs. Until the official
# list arrives the pilot office covers the whole corporation as one group; the
# real constituencies replace this single entry when they are known.
TAMBARAM_AC_MAP = {
    "Tambaram Corporation": [str(w) for w in range(1, 71)],
}

_GEODATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "geodata")

CORPORATIONS: dict[str, dict] = {
    "tambaram": {
        "id": "tambaram",
        "name": "Tambaram City Municipal Corporation",
        "short_name": "Tambaram",
        "geodata_dir": os.path.join(_GEODATA, "tambaram"),
        # Middle of the corporation; the map opens here when GPS is unavailable.
        "center": [12.9376, 80.1355],
        "zoom": 12.5,
        "ac_map": TAMBARAM_AC_MAP,
        "default_constituency": "Tambaram Corporation",
        "default_office": "Tambaram MLA Office",
    },
    "chennai": {
        "id": "chennai",
        "name": "Greater Chennai Corporation",
        "short_name": "Chennai",
        "geodata_dir": _GEODATA,
        "center": [13.0827, 80.2081],
        "zoom": 12.0,
        "ac_map": CHENNAI_AC_MAP,
        "default_constituency": "16 - Egmore",
        "default_office": "Egmore MLA Office",
    },
}

# Tambaram is the pilot, so a fresh database starts there.
DEFAULT_CORPORATION = (os.getenv("DEFAULT_CORPORATION") or "tambaram").strip().lower()
if DEFAULT_CORPORATION not in CORPORATIONS:
    DEFAULT_CORPORATION = "tambaram"

# Every grievance filed before corporations existed was filed in Chennai.
LEGACY_CORPORATION = "chennai"

_SETTING = "active_corporation"


def get(corp_id: str | None) -> dict:
    """The corporation with this id, or the active one when None/unknown."""
    if corp_id and corp_id in CORPORATIONS:
        return CORPORATIONS[corp_id]
    return CORPORATIONS[active_id()]


def active_id(conn=None) -> str:
    """Id of the corporation the apps currently serve."""
    def read(c):
        row = c.execute(
            "SELECT value FROM app_settings WHERE key = ?", (_SETTING,)
        ).fetchone()
        return row[0] if row else None

    try:
        value = read(conn) if conn is not None else _read_fresh(read)
    except Exception:
        value = None  # settings table not created yet
    return value if value in CORPORATIONS else DEFAULT_CORPORATION


def _read_fresh(read):
    with get_connection() as c:
        return read(c)


def set_active(conn, corp_id: str) -> None:
    if corp_id not in CORPORATIONS:
        raise ValueError(f"Unknown corporation '{corp_id}'")
    conn.execute(
        """INSERT INTO app_settings (key, value) VALUES (?, ?)
           ON CONFLICT (key) DO UPDATE SET value = excluded.value""",
        (_SETTING, corp_id),
    )


def ac_map(corp_id: str | None = None) -> dict:
    return get(corp_id)["ac_map"]


def constituencies_for_ward(ward, corp_id: str | None = None) -> list:
    """Every assembly constituency a ward belongs to, within one corporation."""
    if ward is None:
        return []
    key = str(ward).strip()
    return [ac for ac, wards in ac_map(corp_id).items() if key in wards]


def corporation_of_constituency(constituency: str | None) -> str | None:
    """Which corporation a constituency (a tenant's or a coordinator's) is in."""
    name = (constituency or "").strip()
    for cid, corp in CORPORATIONS.items():
        if name in corp["ac_map"]:
            return cid
    return None


def public(corp_id: str | None = None) -> dict:
    """What the apps need to present a corporation."""
    corp = get(corp_id)
    return {
        "id": corp["id"],
        "name": corp["name"],
        "short_name": corp["short_name"],
        "center": corp["center"],
        "zoom": corp["zoom"],
        "constituencies": corp["ac_map"],
    }


def choices() -> list[dict]:
    return [{"id": c["id"], "name": c["name"], "short_name": c["short_name"]}
            for c in CORPORATIONS.values()]
