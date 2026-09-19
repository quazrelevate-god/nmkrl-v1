"""
scripts/migrate_sqlite_to_postgres.py
-------------------------------------
Copy every row from the SQLite database into PostgreSQL, once, at cutover.

    python scripts/migrate_sqlite_to_postgres.py \
        --sqlite /data/fixmystreet.db \
        --database-url postgresql://user:pass@host:5432/railway

What it guarantees
  * The SQLite file is opened READ-ONLY. Nothing here can change the source,
    so a failed or abandoned run leaves the live database exactly as it was.
  * The Postgres schema is built by the app's own init_db(), so the target is
    the schema the app will run against, not a hand-written copy of it.
  * The whole load is ONE transaction. It either lands completely or not at
    all; there is no half-migrated state to clean up.
  * A target that already holds data is refused unless --replace is given, so
    re-running by accident cannot duplicate or clobber anything.
  * Rows whose issue_id points at a grievance that no longer exists cannot
    satisfy Postgres's foreign keys. They are not dropped silently: each one is
    counted in the report and written to a JSON file beside this run.
  * Afterwards every table's row count is compared, and the issues table is
    checksummed (ids, statuses, upvote totals), before anything is committed.

Stop writes to the SQLite database before running it — take the app down or
put it in maintenance — or rows written during the copy will be left behind.
Uploaded media (/data/uploads) is not in the database and is not touched.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(HERE)

# Loaded first so that users, accounts and grievances exist before anything
# that references them. Every other table follows in any order.
PARENTS = ("users", "coordinators", "issues")
# Children holding FOREIGN KEY (issue_id) REFERENCES issues (id).
FK_TO_ISSUES = ("upvotes", "verifications", "issue_events")


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--sqlite", default=os.environ.get("DB_PATH"),
                    help="SQLite file to read (default: $DB_PATH)")
    ap.add_argument("--database-url", default=os.environ.get("DATABASE_URL"),
                    help="Postgres URL to write (default: $DATABASE_URL)")
    ap.add_argument("--replace", action="store_true",
                    help="Empty the Postgres tables first if they hold data")
    ap.add_argument("--batch", type=int, default=5000)
    a = ap.parse_args()
    if not a.sqlite or not os.path.exists(a.sqlite):
        ap.error(f"SQLite file not found: {a.sqlite!r}")
    if not a.database_url or not a.database_url.startswith(("postgres://", "postgresql://")):
        ap.error("--database-url must be a postgres:// or postgresql:// URL")
    return a


def main():
    a = parse_args()
    # database.py decides its dialect from the environment at import time.
    os.environ["DATABASE_URL"] = a.database_url
    sys.path.insert(0, BACKEND)
    import database  # noqa: E402

    import psycopg

    t0 = time.time()
    src = sqlite3.connect(f"file:{a.sqlite}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    print(f"source  {a.sqlite}  ({os.path.getsize(a.sqlite) / 1e6:,.1f} MB, read-only)")
    print(f"target  {_redact(a.database_url)}")

    # 1. Schema, exactly as the app builds it.
    database.init_db()
    print("schema  built by database.init_db()")

    src_tables = [r[0] for r in src.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name")]

    with psycopg.connect(a.database_url) as pg:
        tgt_cols = _target_columns(pg)
        missing = [t for t in src_tables if t not in tgt_cols]
        if missing:
            print(f"warning: in SQLite but not in the app schema, not copied: {missing}")
        tables = [t for t in PARENTS if t in src_tables and t in tgt_cols]
        tables += [t for t in src_tables if t in tgt_cols and t not in PARENTS]

        # 2. Refuse to overwrite live data by accident.
        occupied = {t: n for t in tgt_cols
                    if (n := pg.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0])}
        if occupied and not a.replace:
            sys.exit(f"refusing: Postgres already holds data {occupied}. "
                     "Re-run with --replace to empty it first.")

        with pg.transaction():
            if occupied:
                pg.execute("TRUNCATE " + ", ".join(f'"{t}"' for t in tgt_cols) + " CASCADE")
                print(f"emptied {len(tgt_cols)} target tables (--replace)")

            issue_ids = {r[0] for r in src.execute("SELECT id FROM issues")} \
                if "issues" in src_tables else set()
            report, orphans = {}, {}

            # 3. Copy.
            for t in tables:
                src_cols = [r[1] for r in src.execute(f'PRAGMA table_info("{t}")')]
                cols = [c for c in src_cols if c in tgt_cols[t]]
                dropped = [c for c in src_cols if c not in tgt_cols[t]]
                if dropped:
                    print(f"warning: {t}: columns not in the app schema, not copied: {dropped}")
                types = [tgt_cols[t][c] for c in cols]
                fk_i = cols.index("issue_id") if t in FK_TO_ISSUES and "issue_id" in cols else None

                read = written = 0
                skipped = []
                col_sql = ", ".join(f'"{c}"' for c in cols)
                with pg.cursor().copy(f'COPY "{t}" ({col_sql}) FROM STDIN') as cp:
                    cur = src.execute(f'SELECT {col_sql} FROM "{t}"')
                    while batch := cur.fetchmany(a.batch):
                        for row in batch:
                            read += 1
                            vals = [_coerce(v, ty) for v, ty in zip(row, types)]
                            if fk_i is not None and vals[fk_i] not in issue_ids:
                                skipped.append(dict(zip(cols, row)))
                                continue
                            cp.write_row(vals)
                            written += 1
                report[t] = (read, written)
                if skipped:
                    orphans[t] = skipped
                note = f"  ({len(skipped)} orphaned, see report)" if skipped else ""
                print(f"  {t:<18} {written:>9,} rows{note}")

            # 4. Verify inside the transaction, before committing.
            problems = []
            for t, (read, written) in report.items():
                have = pg.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
                if have != written:
                    problems.append(f"{t}: wrote {written}, table holds {have}")
            if "issues" in report:
                s, p = _issues_digest(src), _issues_digest(pg)
                if s != p:
                    problems.append(f"issues checksum differs: sqlite {s} vs postgres {p}")
                else:
                    print(f"verify  issues checksum matches ({s[:16]}…)")
            if problems:
                # Raising inside pg.transaction() rolls the whole load back.
                raise SystemExit("verification FAILED, nothing committed:\n  " + "\n  ".join(problems))
            print(f"verify  row counts match for all {len(report)} tables")

        pg.execute("ANALYZE")  # give the planner real statistics from day one

    if orphans:
        path = os.path.join(os.getcwd(), f"migration-orphans-{int(t0)}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(orphans, fh, indent=2, default=str)
        total = sum(len(v) for v in orphans.values())
        print(f"orphans {total} rows referenced a grievance that no longer exists; "
              f"not loaded, saved to {path}")
    print(f"done    committed in {time.time() - t0:.1f}s")


def _target_columns(pg):
    out = {}
    for t, c, ty in pg.execute(
        "SELECT table_name, column_name, data_type FROM information_schema.columns "
        "WHERE table_schema = 'public'"
    ):
        out.setdefault(t, {})[c] = ty
    return out


def _coerce(v, pg_type):
    """SQLite stores whatever it is given; Postgres checks. Normalise the values
    SQLite let through — '' or '12' in an INTEGER column, a number in a TEXT
    column — into what the target column actually holds."""
    if v is None:
        return None
    if pg_type in ("integer", "bigint", "smallint"):
        if isinstance(v, str):
            v = v.strip()
            if v == "":
                return None
            return int(float(v))
        return int(v)
    if pg_type in ("double precision", "real", "numeric"):
        if isinstance(v, str) and v.strip() == "":
            return None
        return float(v)
    if pg_type == "text" and not isinstance(v, str):
        return str(v)
    return v


def _issues_digest(conn) -> str:
    """Order-independent fingerprint of the grievance table's identity and state."""
    h = hashlib.sha256()
    for r in conn.execute(
        "SELECT id, status, upvotes, COALESCE(assigned_coordinator, ''), "
        "COALESCE(created_by, '') FROM issues ORDER BY id"
    ):
        h.update("|".join("" if x is None else str(x) for x in r).encode())
        h.update(b"\n")
    return h.hexdigest()


def _redact(url: str) -> str:
    if "@" in url and "://" in url:
        scheme, rest = url.split("://", 1)
        return f"{scheme}://***@{rest.split('@', 1)[1]}"
    return url


if __name__ == "__main__":
    main()
