import os
import sqlite3
from contextlib import contextmanager

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "fixmystreet.db")


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
"""


def init_db() -> None:
    with get_connection() as conn:
        conn.executescript(SCHEMA)
        for col, defn in [
            ("area_name", "TEXT DEFAULT ''"),
            ("phone", "TEXT DEFAULT ''"),
            ("ward_no", "INTEGER"),
            ("department", "TEXT DEFAULT ''"),
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
