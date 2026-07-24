import os
import sqlite3
from contextlib import contextmanager

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
# Persistence path resolution (in priority order):
#   1. DB_PATH env var — explicit override.
#   2. A mounted /data volume (Railway) — auto-detected so it works even if the
#      env var isn't applied.
#   3. Local file — development default.
DB_PATH = (
    os.environ.get("DB_PATH")
    or ("/data/fixmystreet.db" if os.path.isdir("/data") else None)
    or os.path.join(BASE_DIR, "fixmystreet.db")
)


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


@contextmanager
def get_connection():
    conn = _connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_db():
    conn = _connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


SCHEMA = """
-- Phase-1 citizen accounts: one row per phone number. Login checks the
-- (phone, name) pair — a known phone must present its registered name; an
-- unknown phone auto-registers. OTP is a static mock in phase 1.
CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT NOT NULL UNIQUE,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS issues (
    id                  TEXT PRIMARY KEY,
    title               TEXT,
    image_url           TEXT,
    audio_url           TEXT,
    transcript          TEXT,
    summary_highlights  TEXT,
    latitude            REAL NOT NULL,
    longitude           REAL NOT NULL,
    area_name           TEXT DEFAULT '',
    status              TEXT NOT NULL DEFAULT 'ACTIVE',
    upvotes             INTEGER NOT NULL DEFAULT 0,
    notify_reporter     INTEGER NOT NULL DEFAULT 0,
    created_at          TEXT NOT NULL,
    created_by          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS upvotes (
    id        TEXT PRIMARY KEY,
    user_id   TEXT NOT NULL,
    issue_id  TEXT NOT NULL,
    name      TEXT DEFAULT '',
    UNIQUE (user_id, issue_id),
    FOREIGN KEY (issue_id) REFERENCES issues (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS verifications (
    id         TEXT PRIMARY KEY,
    issue_id   TEXT NOT NULL,
    user_id    TEXT NOT NULL,
    response   TEXT NOT NULL,
    timestamp  TEXT NOT NULL,
    FOREIGN KEY (issue_id) REFERENCES issues (id) ON DELETE CASCADE
);

-- Every /api/locate lookup is logged with the real GCC zone/ward the
-- coordinate resolved to (via point-in-polygon over the KML boundaries).
CREATE TABLE IF NOT EXISTS location_logs (
    id                   TEXT PRIMARY KEY,
    latitude             REAL NOT NULL,
    longitude            REAL NOT NULL,
    detected_zone        TEXT,
    detected_zone_name   TEXT,
    detected_ward        TEXT,
    assembly_constituency TEXT,
    created_at           TEXT NOT NULL
);
"""


def init_db() -> None:
    with get_connection() as conn:
        conn.executescript(SCHEMA)
        for col, defn in [
            ("area_name", "TEXT DEFAULT ''"),
            ("phone", "TEXT DEFAULT ''"),
            ("ward_no", "INTEGER"),
            ("department", "TEXT DEFAULT ''"),
            ("zone", "TEXT DEFAULT ''"),
            ("zone_name", "TEXT DEFAULT ''"),
            ("name", "TEXT DEFAULT ''"),  # reporter's name (personal detail)
            # Coordinator-facing message surfaced to the citizen (e.g. after a
            # 'redirect' the citizen sees a delay-apology; after 'transfer' the
            # citizen sees the department the ticket was routed to).
            ("coordinator_message", "TEXT DEFAULT ''"),
        ]:
            try:
                conn.execute(f"ALTER TABLE issues ADD COLUMN {col} {defn}")
            except Exception:
                pass
        # upvotes.name carries the verified upvoter name (OTP-gated public upvotes).
        try:
            conn.execute("ALTER TABLE upvotes ADD COLUMN name TEXT DEFAULT ''")
        except Exception:
            pass
        # location_logs gains the primary Assembly Constituency for the lookup.
        try:
            conn.execute("ALTER TABLE location_logs ADD COLUMN assembly_constituency TEXT")
        except Exception:
            pass
