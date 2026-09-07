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

-- Constituency-staff accounts, created from the admin console. Auth is
-- POC-grade plain-text (documented). One coordinator per (username).
-- constituency is a fixed assignment; home_ward is the default ward that
-- opens on sign-in (the coordinator can switch wards WITHIN their AC).
CREATE TABLE IF NOT EXISTS coordinators (
    id                    TEXT PRIMARY KEY,
    username              TEXT NOT NULL UNIQUE,
    password              TEXT NOT NULL,
    name                  TEXT NOT NULL,
    role                  TEXT NOT NULL,
    constituency          TEXT NOT NULL,
    home_ward             TEXT NOT NULL,
    must_change_password  INTEGER NOT NULL DEFAULT 1,
    created_at            TEXT NOT NULL
);

-- Phone-number OTP challenge store for citizen login (one row per phone;
-- the latest request replaces the previous). OTP is stored HASHED.
CREATE TABLE IF NOT EXISTS otp_codes (
    phone       TEXT PRIMARY KEY,
    otp_hash    TEXT NOT NULL,
    expires_at  TEXT NOT NULL,
    attempts    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
);

-- Real-time-ish push queue polled by the citizen + coordinator apps.
--   recipient_type: 'citizen' | 'coordinator'
--   recipient_id:   citizen user_id, or coordinator username
--   kind: 'status_change' | 'new_grievance' | 'assigned' | 'closed' | 'transfer'
CREATE TABLE IF NOT EXISTS notifications (
    id             TEXT PRIMARY KEY,
    recipient_type TEXT NOT NULL,
    recipient_id   TEXT NOT NULL,
    kind           TEXT NOT NULL,
    issue_id       TEXT NOT NULL,
    title          TEXT DEFAULT '',
    message        TEXT DEFAULT '',
    data           TEXT DEFAULT '{}',
    created_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notif_recipient
    ON notifications (recipient_type, recipient_id, created_at DESC);

-- FCM registration tokens, one row per (device, signed-in account). Mirrors the
-- notifications recipient shape so a push target is a straight lookup. Rows are
-- deleted on sign-out and whenever FCM reports a token as UNREGISTERED, so a
-- device never keeps receiving alerts for an account that left it.
CREATE TABLE IF NOT EXISTS device_tokens (
    token          TEXT PRIMARY KEY,
    recipient_type TEXT NOT NULL,
    recipient_id   TEXT NOT NULL,
    platform       TEXT DEFAULT 'android',
    updated_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_devtok_recipient
    ON device_tokens (recipient_type, recipient_id);

-- Responsible-officer contacts for the department taxonomy, entered in the
-- admin Departmental Configuration page. Keyed by "<Dept>||<SubDept>||<Officer>"
-- (mirrors the frontend contactKey), one name + mobile per officer slot.
CREATE TABLE IF NOT EXISTS dept_officers (
    contact_key  TEXT PRIMARY KEY,
    name         TEXT DEFAULT '',
    mobile       TEXT DEFAULT '',
    updated_at   TEXT NOT NULL
);

-- Append-only audit trail: one row per state-changing action on a grievance,
-- by anyone (coordinator, citizen, admin). The issues table only ever holds
-- the LATEST value of coordinator_message / department / status, so without
-- this the note a coordinator wrote at transfer time is destroyed by the next
-- action. Evidence captured in the coordinator app's action sheets (live photo
-- + voice note) is attached to the event that required it.
--   actor_type: 'coordinator' | 'citizen' | 'admin' | 'system'
--   actor_id:   coordinator username, or citizen user_id
--   action:     verify | transfer | escalate | redirect | close | mark_false
--               | citizen_approve | citizen_reject | report
CREATE TABLE IF NOT EXISTS issue_events (
    id          TEXT PRIMARY KEY,
    issue_id    TEXT NOT NULL,
    actor_type  TEXT NOT NULL,
    actor_id    TEXT NOT NULL DEFAULT '',
    action      TEXT NOT NULL,
    from_status TEXT DEFAULT '',
    to_status   TEXT DEFAULT '',
    note        TEXT DEFAULT '',
    department  TEXT DEFAULT '',
    officer     TEXT DEFAULT '',
    image_url   TEXT,
    audio_url   TEXT,
    created_at  TEXT NOT NULL,
    FOREIGN KEY (issue_id) REFERENCES issues (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_events_issue
    ON issue_events (issue_id, created_at);
CREATE INDEX IF NOT EXISTS idx_events_actor
    ON issue_events (actor_type, actor_id, created_at DESC);

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
            # Coordinator who took ownership (username) — set by
            # POST /api/coordinator/issues/{id}/verify. When non-null, the
            # ticket disappears from every OTHER coordinator's ward tab.
            ("assigned_coordinator", "TEXT DEFAULT ''"),
            # Non-null when a coordinator escalated the ticket; the mobile app
            # groups these into a dedicated "Escalated" tab.
            ("escalated_at", "TEXT"),
            # Human-friendly tracking id (FMS-XXXXXXXX), assigned at insert and
            # stored so every surface fetches the SAME value from the DB.
            ("ticket_number", "TEXT DEFAULT ''"),
            # Tamil translation of the transcript (Gemini returns both at
            # report time); shown when the app is in Tamil mode.
            ("transcript_ta", "TEXT DEFAULT ''"),
            # Non-null when the citizen REJECTED a coordinator's closure — the
            # coordinator app surfaces an alert and moves it back to Assigned.
            ("rejected_at", "TEXT"),
            # Responsible officer chosen during a Dept. Transfer. Previously this
            # only ever existed inside the prose of coordinator_message, so it
            # could not be filtered, counted or shown as a field.
            ("responsible_officer", "TEXT DEFAULT ''"),
            # Lifecycle timestamps. created_at alone cannot answer "how long did
            # this take?" — every admin duration metric needs these.
            ("assigned_at", "TEXT"),      # coordinator took ownership (verify)
            ("transferred_at", "TEXT"),   # routed to a department
            ("closed_at", "TEXT"),        # coordinator marked it done
            ("resolved_at", "TEXT"),      # citizen APPROVED the closure
            # Closure evidence: the live photo + voice note the coordinator app
            # makes MANDATORY before a ticket can be closed. Denormalised from
            # the close event so admin lists can show it without a join.
            ("closure_image_url", "TEXT"),
            ("closure_audio_url", "TEXT"),
            # An optional written petition the citizen attaches at report time
            # (PDF, doc or a scan). Optional by design — the photo and voice
            # note stay the required pair; this is for people who arrive with
            # paperwork already written.
            ("document_url", "TEXT"),
            ("document_name", "TEXT DEFAULT ''"),
        ]:
            try:
                conn.execute(f"ALTER TABLE issues ADD COLUMN {col} {defn}")
            except Exception:
                pass
        # Account state. Admin's enable/disable was a per-browser flag with no
        # column behind it, so a "disabled" coordinator went on signing into the
        # mobile app and working normally. Revocation needs somewhere to live.
        try:
            conn.execute(
                "ALTER TABLE coordinators ADD COLUMN status TEXT NOT NULL DEFAULT 'active'"
            )
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
        _reconcile_upvotes(conn)


# Names used for the backfilled seed supporters (see _reconcile_upvotes).
_SEED_SUPPORTERS = [
    "Aarthi", "Bala", "Chitra", "Dinesh", "Elango", "Gayathri", "Hari",
    "Iniya", "Jeeva", "Kavitha", "Lakshmi", "Murugan", "Nithya", "Pandian",
    "Revathi", "Saravanan", "Thendral", "Umesh", "Vasanth", "Yamuna",
]


def _reconcile_upvotes(conn) -> None:
    """Make `issues.upvotes` and the `upvotes` table agree.

    The demo data was seeded by writing a support COUNT straight onto each
    issue without inserting the rows behind it, so the counter and the table
    told different stories: 747 grievances showed a total the `upvotes` table
    could not account for. Anything reading the rows — "My Supports", the
    per-user stats, the one-vote-per-person guard — was working from a
    different number than the badge the citizen actually saw.

    The counter is treated as the truth (it is what the whole demo is sorted
    and prioritised by) and the missing rows are materialised under reserved
    `seed:` ids that can never collide with a real account. Where rows somehow
    outnumber the counter, the counter is raised instead — never lowered, so a
    real vote is never discarded.

    Idempotent: once the two agree there is nothing to do, and every live
    upvote writes both halves, so this only ever fixes historic seed data.
    """
    drifted = conn.execute(
        """SELECT i.id, i.upvotes AS stored,
                  (SELECT COUNT(*) FROM upvotes u WHERE u.issue_id = i.id) AS actual
             FROM issues i
            WHERE i.upvotes <> (SELECT COUNT(*) FROM upvotes u WHERE u.issue_id = i.id)"""
    ).fetchall()
    if not drifted:
        return
    import uuid

    added = raised = 0
    for row in drifted:
        gap = row["stored"] - row["actual"]
        if gap < 0:
            conn.execute(
                "UPDATE issues SET upvotes = ? WHERE id = ?", (row["actual"], row["id"])
            )
            raised += 1
            continue
        short = row["id"].replace("-", "")[:8]
        for n in range(gap):
            conn.execute(
                """INSERT OR IGNORE INTO upvotes (id, user_id, issue_id, name)
                   VALUES (?, ?, ?, ?)""",
                (
                    str(uuid.uuid4()),
                    f"seed:{short}:{n}",
                    row["id"],
                    _SEED_SUPPORTERS[n % len(_SEED_SUPPORTERS)],
                ),
            )
            added += 1
    print(f"[migrate] upvotes reconciled: +{added} rows, {raised} counters corrected")
