"""
routers/admin.py
----------------
Authority/triage endpoints:
  * GET  /api/admin/issues               - filterable queue (all statuses)
  * POST /api/admin/issues/{id}/verify   - SUBMITTED -> ACTIVE (approve grievance)
  * POST /api/admin/issues/{id}/close    - mark resolved -> PENDING_VERIFICATION
  * POST /api/admin/issues/{id}/progress - ACTIVE -> IN_PROGRESS
  * GET  /api/admin/issues/{id}/timeline - append-only action history
  * GET  /api/admin/coordinator-performance - per-coordinator workload + outcomes
  * POST /api/admin/issues/{id}/summarise-document - read the attached petition
  * GET  /api/admin/issues/{id}/duplicate - the suspected original + merged-in reports
  * POST /api/admin/issues/{id}/merge    - fold a duplicate into the original
  * POST /api/admin/issues/{id}/keep-separate - rule that it is its own problem
  * POST /api/admin/issues/{id}/unmerge  - reverse a merge
  * POST /api/admin/issues/{id}/reprocess - retry a failed transcription/routing
"""

from fastapi import (
    APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query,
    UploadFile,
)
from pydantic import BaseModel

import json
import os

import audit
import duplicates
from database import get_db
from routers.notifications import emit_status_change, emit_to_coordinator
from utils import CHENNAI_AC_MAP, now_iso, read_upload, serialize_issue

router = APIRouter(prefix="/api/admin", tags=["admin"])

VALID_STATUSES = {
    "SUBMITTED", "ACTIVE", "FORWARDED", "IN_PROGRESS",
    "PENDING_VERIFICATION", "CLOSED", "FALSE", "MERGED",
}


@router.get("/issues")
def list_admin_issues(
    status: str = Query(None),
    sort: str = Query("upvotes"),
    zone: str = Query(None),
    ward: int = Query(None),
    coordinator: str = Query(None),
    department: str = Query(None),
    constituency: str = Query(None),
    q: str = Query(None),
    unassigned: bool = Query(False),
    since: str = Query(None),
    board: bool = Query(False),
    limit: int = Query(None),
    offset: int = Query(0),
    conn=Depends(get_db),
):
    """
    Return issues with optional filtering — the single source the admin console
    reads for every grievance surface (tickets, petition review, routing, KPIs).

    - status: SUBMITTED, ACTIVE, FORWARDED, IN_PROGRESS, PENDING_VERIFICATION,
      CLOSED, FALSE — or omit for ALL issues (dashboard/heatmap needs the full set).
    - zone: single GCC zone (roman numeral, e.g. "VIII").
    - ward: single ward number.
    - coordinator: grievances owned by this coordinator username.
    - department: grievances routed to this department (matches issues.department).
    - constituency: Assembly Constituency name — expands to that AC's wards.
    - q: free-text search across ticket_number, title, reporter name and phone.
    - sort: 'upvotes' (default) or 'recent'
    - limit / offset: OPT-IN pagination. Omit `limit` and the full matching set
      is returned exactly as before (the dashboard and heatmap need every row).
      Pass a `limit` to page the tickets/users surfaces — the response then also
      carries `total`, `limit`, `offset` and `has_more`.
    """
    clauses, params = [], []
    if status and status.upper() in VALID_STATUSES:
        clauses.append("status = ?")
        params.append(status.upper())
    if zone:
        clauses.append("zone = ?")
        params.append(zone)
    if ward is not None:
        clauses.append("ward_no = ?")
        params.append(ward)
    if coordinator:
        clauses.append("assigned_coordinator = ?")
        params.append(coordinator)
    if department:
        clauses.append("department = ?")
        params.append(department)
    if constituency:
        wards = CHENNAI_AC_MAP.get(constituency, [])
        if wards:
            placeholders = ",".join("?" for _ in wards)
            clauses.append(f"CAST(ward_no AS TEXT) IN ({placeholders})")
            params.extend(wards)
        else:
            # Unknown AC name → no matches, rather than silently returning all.
            clauses.append("1 = 0")
    if q:
        needle = f"%{q.strip().lower()}%"
        clauses.append(
            "(LOWER(COALESCE(ticket_number,'')) LIKE ? OR LOWER(COALESCE(title,'')) LIKE ?"
            " OR LOWER(COALESCE(name,'')) LIKE ? OR COALESCE(phone,'') LIKE ?)"
        )
        params.extend([needle, needle, needle, needle])
    if unassigned:
        clauses.append("(assigned_coordinator IS NULL OR assigned_coordinator = '')")
    if since:
        clauses.append("created_at >= ?")
        params.append(since)
    if board:
        # The Tickets board is everything past verification — SUBMITTED lives in
        # Petition Review and FALSE/MERGED are off the queue. Lets the "All" tab
        # page server-side instead of pulling every row to filter in the browser.
        clauses.append(
            "status IN ('ACTIVE','FORWARDED','IN_PROGRESS','PENDING_VERIFICATION','CLOSED')"
        )

    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    # Sort in SQL, not in Python: the old code pulled every row and sorted the
    # whole list on each console load. 'upvotes' mirrors the old key exactly
    # (highest support first, oldest breaking ties).
    order = "created_at DESC" if sort == "recent" else "upvotes DESC, created_at ASC"
    sql = f"SELECT * FROM issues{where} ORDER BY {order}"

    # Opt-in pagination — see the docstring. With no `limit` the shape and
    # contents are exactly what every current caller already gets.
    if limit is not None and limit > 0:
        total = conn.execute(
            f"SELECT COUNT(*) AS c FROM issues{where}", params
        ).fetchone()["c"]
        offset = max(0, offset)
        rows = conn.execute(
            sql + " LIMIT ? OFFSET ?", [*params, limit, offset]
        ).fetchall()
        issues = [serialize_issue(r) for r in rows]
        return {
            "count": len(issues), "issues": issues,
            "total": total, "limit": limit, "offset": offset,
            "has_more": offset + len(issues) < total,
        }

    rows = conn.execute(sql, params).fetchall()
    issues = [serialize_issue(r) for r in rows]
    return {"count": len(issues), "issues": issues}


@router.get("/issues/stats")
def admin_issue_stats(
    zone: str = Query(None),
    ward: int = Query(None),
    coordinator: str = Query(None),
    department: str = Query(None),
    constituency: str = Query(None),
    q: str = Query(None),
    unassigned: bool = Query(False),
    since: str = Query(None),
    conn=Depends(get_db),
):
    """Per-status counts for the ticket queue, so the console's tab badges stay
    accurate while the list itself is paged. Applies the same scoping filters as
    /issues (everything EXCEPT status — status is what we're counting), then
    GROUPs BY status in SQL. One cheap aggregate instead of shipping every row to
    the browser to be counted there.
    """
    clauses, params = [], []
    if zone:
        clauses.append("zone = ?"); params.append(zone)
    if ward is not None:
        clauses.append("ward_no = ?"); params.append(ward)
    if coordinator:
        clauses.append("assigned_coordinator = ?"); params.append(coordinator)
    if department:
        clauses.append("department = ?"); params.append(department)
    if constituency:
        wards = CHENNAI_AC_MAP.get(constituency, [])
        if wards:
            placeholders = ",".join("?" for _ in wards)
            clauses.append(f"CAST(ward_no AS TEXT) IN ({placeholders})")
            params.extend(wards)
        else:
            clauses.append("1 = 0")
    if q:
        needle = f"%{q.strip().lower()}%"
        clauses.append(
            "(LOWER(COALESCE(ticket_number,'')) LIKE ? OR LOWER(COALESCE(title,'')) LIKE ?"
            " OR LOWER(COALESCE(name,'')) LIKE ? OR COALESCE(phone,'') LIKE ?)"
        )
        params.extend([needle, needle, needle, needle])
    if unassigned:
        clauses.append("(assigned_coordinator IS NULL OR assigned_coordinator = '')")
    if since:
        clauses.append("created_at >= ?"); params.append(since)
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    rows = conn.execute(
        f"SELECT status, COUNT(*) AS c FROM issues{where} GROUP BY status", params
    ).fetchall()
    counts = {r["status"]: r["c"] for r in rows}
    return {"total": sum(counts.values()), "counts": counts}


@router.get("/users")
def list_users(
    q: str = Query(None),
    limit: int = Query(None),
    offset: int = Query(0),
    conn=Depends(get_db),
):
    """
    List citizen accounts with per-user grievance counters, so the admin console
    can show real 'user related data' (who reported, how much, how much resolved).

    Counters are computed from the issues table keyed on issues.created_by = users.id:
      - reports:  total grievances submitted
      - resolved: grievances now CLOSED
      - open:     grievances not yet CLOSED/FALSE
    Optional q filters by name or phone. limit/offset are opt-in pagination, as
    on /issues — omit `limit` for the full list, unchanged.
    """
    clauses, params = [], []
    if q:
        needle = f"%{q.strip().lower()}%"
        clauses.append("(LOWER(name) LIKE ? OR phone LIKE ?)")
        params.extend([needle, needle])
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    sql = f"SELECT id, name, phone, created_at FROM users{where} ORDER BY created_at DESC"

    total = None
    if limit is not None and limit > 0:
        total = conn.execute(
            f"SELECT COUNT(*) AS c FROM users{where}", params
        ).fetchone()["c"]
        offset = max(0, offset)
        users = [
            dict(r) for r in conn.execute(
                sql + " LIMIT ? OFFSET ?", [*params, limit, offset]
            ).fetchall()
        ]
    else:
        users = [dict(r) for r in conn.execute(sql, params).fetchall()]

    # Aggregate grievance counts per user. When a page was requested, scope the
    # aggregate to just that page's ids so a city-scale issues table is not
    # scanned to decorate 25 rows; otherwise one GROUP BY over the whole table.
    agg = {}
    if total is not None:
        ids = [u["id"] for u in users if u["id"]]
        agg_rows = []
        if ids:
            ph = ",".join("?" for _ in ids)
            agg_rows = conn.execute(
                f"""SELECT created_by,
                           COUNT(*) AS reports,
                           SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) AS resolved,
                           SUM(CASE WHEN status NOT IN ('CLOSED','FALSE') THEN 1 ELSE 0 END) AS open
                      FROM issues
                     WHERE created_by IN ({ph})
                  GROUP BY created_by""",
                ids,
            ).fetchall()
    else:
        agg_rows = conn.execute(
            """SELECT created_by,
                      COUNT(*) AS reports,
                      SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) AS resolved,
                      SUM(CASE WHEN status NOT IN ('CLOSED','FALSE') THEN 1 ELSE 0 END) AS open
                 FROM issues
                WHERE created_by IS NOT NULL AND created_by != ''
             GROUP BY created_by"""
        ).fetchall()
    for row in agg_rows:
        agg[row["created_by"]] = {
            "reports": row["reports"] or 0,
            "resolved": row["resolved"] or 0,
            "open": row["open"] or 0,
        }

    for u in users:
        stats = agg.get(u["id"], {"reports": 0, "resolved": 0, "open": 0})
        u.update(stats)

    if total is not None:
        return {
            "count": len(users), "users": users,
            "total": total, "limit": limit, "offset": offset,
            "has_more": offset + len(users) < total,
        }
    return {"count": len(users), "users": users}


def _announce(conn, row, kind: str, citizen_msg: str, coord_msg: str,
              action: str, from_status: str, *, note=None,
              image_url=None, audio_url=None) -> None:
    """Tell everyone attached to a grievance that admin moved it.

    All four admin actions changed the status and told nobody: the citizen
    watching their report and the coordinator holding it both had to reload by
    hand to notice. They also left no trace in the history, so an admin move
    was the one transition the timeline could not explain.
    """
    try:
        emit_status_change(conn, row, kind, citizen_msg)
        emit_to_coordinator(conn, row, kind, coord_msg)
    except Exception:
        pass  # best-effort; never fail the state change behind it
    audit.record(
        conn, row["id"], action=action, actor_type="admin", actor_id="admin",
        from_status=from_status, to_status=row["status"],
        # An action that carries its own words and proof logs those, as the
        # coordinator's close does; the rest log the alert they sent.
        note=coord_msg if note is None else note,
        image_url=image_url, audio_url=audio_url,
    )


@router.post("/issues/{issue_id}/verify")
def verify_grievance(issue_id: str, conn=Depends(get_db)):
    """Authority approves a freshly submitted grievance: SUBMITTED -> ACTIVE.

    This is the gate that makes the issue public — only now does its pin
    appear on the citizen map and the status tracker advance to 'Assigned'.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] != "SUBMITTED":
        raise HTTPException(
            status_code=409,
            detail=f"Only SUBMITTED grievances can be verified (status={issue['status']})",
        )
    conn.execute("UPDATE issues SET status = 'ACTIVE' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    _announce(conn, row, "assigned",
              "Your grievance has been verified and is now public.",
              "A grievance in your ward was verified by the MLA office.",
              "admin_verify", issue["status"])
    return serialize_issue(row)


@router.post("/issues/{issue_id}/forward")
def forward_issue(issue_id: str, conn=Depends(get_db)):
    """Forward a verified grievance to its routed department: ACTIVE -> FORWARDED.

    This is the hand-off step (the WhatsApp/department dispatch) — it marks the
    ticket as forwarded so it shows under the 'Forwarded' queue.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "IN_PROGRESS"):
        raise HTTPException(
            status_code=409,
            detail=f"Only open tickets can be forwarded (status={issue['status']})",
        )
    # Stamp the hand-off, as the coordinator's transfer does. Status alone
    # cannot say a ticket was dispatched once it has moved on to IN_PROGRESS,
    # and the console switches dispatch to "Chat with officer" on this.
    conn.execute(
        "UPDATE issues SET status = 'FORWARDED', transferred_at = ? WHERE id = ?",
        (now_iso(), issue_id),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    _announce(conn, row, "transfer",
              "Your grievance was forwarded to the responsible department.",
              "A grievance you hold was forwarded by the MLA office.",
              "admin_forward", issue["status"])
    return serialize_issue(row)


@router.post("/issues/{issue_id}/assign")
def assign_coordinator(
    issue_id: str,
    coordinator: str = Form(""),
    conn=Depends(get_db),
):
    """MLA office assigns (or reassigns) a grievance to a coordinator.

    Assignment used to happen only one way — a coordinator self-claiming an
    unassigned ward grievance in the mobile app. The MLA office had no way to
    hand a specific grievance to a specific coordinator from the console, which
    is exactly what the constituency model needs: any coordinator in the AC can
    be pointed at any grievance. This is that control.

    `coordinator` empty un-assigns. A real, active account is required otherwise.
    Assignment is orthogonal to the lifecycle — it never changes the status — and
    terminal grievances (closed / false / merged) cannot be reassigned.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] in ("CLOSED", "FALSE", "MERGED"):
        raise HTTPException(
            status_code=409,
            detail=f"A {issue['status'].lower()} grievance cannot be reassigned.",
        )
    who = (coordinator or "").strip().lower()
    if who:
        crow = conn.execute(
            "SELECT username, status FROM coordinators WHERE LOWER(username) = ?", (who,)
        ).fetchone()
        if crow is None:
            raise HTTPException(status_code=400, detail=f"Unknown coordinator '{who}'.")
        if (crow["status"] or "active").lower() != "active":
            raise HTTPException(
                status_code=400, detail="That coordinator account is disabled."
            )
        conn.execute(
            "UPDATE issues SET assigned_coordinator = ?, "
            "assigned_at = COALESCE(assigned_at, ?) WHERE id = ?",
            (who, now_iso(), issue_id),
        )
        note = f"Assigned to @{who} by the MLA office."
    else:
        conn.execute(
            "UPDATE issues SET assigned_coordinator = '' WHERE id = ?", (issue_id,)
        )
        note = "Unassigned by the MLA office."
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    # Notify the newly-assigned coordinator (the updated row now names them); an
    # unassign has no owner to tell. Best-effort — never fail the assignment.
    if who:
        try:
            emit_to_coordinator(
                conn, row, "assigned",
                "The MLA office assigned this grievance to you.",
            )
        except Exception:
            pass
    audit.record(
        conn, issue_id, action="assign", actor_type="admin", actor_id="admin",
        from_status=issue["status"], to_status=row["status"], note=note,
    )
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
async def close_issue(
    issue_id: str,
    note: str = Form(""),
    photo: UploadFile = File(None),
    voice: UploadFile = File(None),
    conn=Depends(get_db),
):
    """Mark resolved, with proof of work.

    The coordinator app has required a photo and a note to close since the
    evidence work; admin could close with nothing at all, which made the two
    routes to the same status mean different things. The console now demands
    the same proof, and it is stored in the same columns so the citizen and the
    timeline see one kind of closure however it was reached.
    """
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "FORWARDED", "IN_PROGRESS"):
        raise HTTPException(
            status_code=409,
            detail=f"Only open issues can be resolved (status={issue['status']})",
        )
    image_url, audio_url = await audit.store_evidence(photo, voice)
    conn.execute(
        """UPDATE issues
              SET status = 'PENDING_VERIFICATION', notify_reporter = 1,
                  closed_at = ?, coordinator_message = ?,
                  closure_image_url = COALESCE(?, closure_image_url),
                  closure_audio_url = COALESCE(?, closure_audio_url)
            WHERE id = ?""",
        (now_iso(), note.strip(), image_url, audio_url, issue_id),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    _announce(conn, row, "closed",
              "Your grievance is marked resolved — please approve or reject to confirm.",
              "A grievance you hold was closed by the MLA office.",
              "admin_close", issue["status"],
              note=note.strip(), image_url=image_url, audio_url=audio_url)
    result = serialize_issue(row)
    result["notification_sent_to"] = issue["created_by"]
    return result


@router.post("/issues/{issue_id}/progress")
def mark_in_progress(issue_id: str, conn=Depends(get_db)):
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "FORWARDED"):
        raise HTTPException(
            status_code=409,
            detail=f"Only ACTIVE/FORWARDED issues can move to IN_PROGRESS (status={issue['status']})",
        )
    conn.execute("UPDATE issues SET status = 'IN_PROGRESS' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    _announce(conn, row, "escalated",
              "Work has started on your grievance.",
              "A grievance you hold moved to In Progress.",
              "admin_progress", issue["status"])
    return serialize_issue(row)


# ── Responsible-officer contacts (Departmental Configuration page) ────────────

class OfficerContact(BaseModel):
    key: str            # "<Dept>||<SubDept>||<Officer>" — mirrors frontend contactKey
    name: str = ""
    mobile: str = ""


@router.get("/officers")
def list_officers(conn=Depends(get_db)):
    """Return every configured officer contact as a { key: {name, mobile} } map —
    the same shape the admin Departments page used to keep in localStorage, so it
    now shares one source of truth across browsers."""
    rows = conn.execute("SELECT contact_key, name, mobile FROM dept_officers").fetchall()
    contacts = {r["contact_key"]: {"name": r["name"] or "", "mobile": r["mobile"] or ""} for r in rows}
    return {"count": len(contacts), "contacts": contacts}


@router.put("/officers")
def upsert_officer(body: OfficerContact, conn=Depends(get_db)):
    """Create/update a single officer contact (name + mobile) by its key."""
    if not body.key or body.key.count("||") != 2:
        raise HTTPException(status_code=400, detail="key must be '<Dept>||<SubDept>||<Officer>'")
    conn.execute(
        """INSERT INTO dept_officers (contact_key, name, mobile, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(contact_key) DO UPDATE SET
               name = excluded.name, mobile = excluded.mobile, updated_at = excluded.updated_at""",
        (body.key, body.name or "", body.mobile or "", now_iso()),
    )
    return {"key": body.key, "name": body.name or "", "mobile": body.mobile or ""}


@router.get("/issues/{issue_id}/timeline")
def issue_timeline(issue_id: str, conn=Depends(get_db)):
    """Full action history for one grievance, oldest first.

    The issues row only keeps the LATEST coordinator_message, so this is the
    only surface that can show what a coordinator wrote at transfer time after
    a later escalate overwrote it, together with the closure photo/voice.
    """
    if conn.execute("SELECT 1 FROM issues WHERE id = ?", (issue_id,)).fetchone() is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    return {"issue_id": issue_id, "events": audit.timeline(conn, issue_id)}


def _avg_hours(rows, start_col: str, end_col: str):
    """Mean hours between two ISO timestamps, ignoring rows missing either."""
    from datetime import datetime
    spans = []
    for r in rows:
        a, b = r[start_col], r[end_col]
        if not a or not b:
            continue
        try:
            spans.append((datetime.fromisoformat(b) - datetime.fromisoformat(a)).total_seconds() / 3600)
        except ValueError:
            continue
    if not spans:
        return None
    return round(sum(spans) / len(spans), 1)


@router.get("/coordinator-performance")
def coordinator_performance(conn=Depends(get_db)):
    """Per-coordinator workload and outcomes.

    Admin could see WHO a grievance was assigned to but never how any one
    coordinator was doing: the counts had to be eyeballed from the petition
    list. This aggregates the same rows the coordinator app acts on, so the
    numbers cannot drift from what the field sees.

    Every coordinator account appears, including those with nothing assigned
    yet — an empty row is a real answer, not a missing one.
    """
    coords = conn.execute(
        """SELECT username, name, role, constituency, home_ward
             FROM coordinators ORDER BY LOWER(name)"""
    ).fetchall()

    stats = []
    for c in coords:
        uname = (c["username"] or "").strip().lower()
        rows = conn.execute(
            "SELECT * FROM issues WHERE LOWER(assigned_coordinator) = ?", (uname,)
        ).fetchall()
        by_status = {}
        for r in rows:
            by_status[r["status"]] = by_status.get(r["status"], 0) + 1
        actions = {
            a["action"]: a["n"] for a in conn.execute(
                """SELECT action, COUNT(*) AS n FROM issue_events
                    WHERE actor_type = 'coordinator' AND actor_id = ?
                    GROUP BY action""",
                (uname,),
            ).fetchall()
        }
        closed = by_status.get("PENDING_VERIFICATION", 0) + by_status.get("CLOSED", 0)
        assigned = len(rows)
        stats.append({
            "username": uname,
            "name": c["name"],
            "role": c["role"],
            "constituency": c["constituency"],
            "home_ward": c["home_ward"],
            "assigned": assigned,
            "open": by_status.get("ACTIVE", 0) + by_status.get("SUBMITTED", 0),
            "forwarded": by_status.get("FORWARDED", 0),
            "escalated": by_status.get("IN_PROGRESS", 0),
            "awaiting_citizen": by_status.get("PENDING_VERIFICATION", 0),
            "resolved": by_status.get("CLOSED", 0),
            "false_petitions": by_status.get("FALSE", 0),
            "rejected_by_citizen": sum(1 for r in rows if r["rejected_at"]),
            # Proof-of-work: closures that actually carry the photo + voice the
            # app demands before a ticket can be closed.
            "closures_with_evidence": sum(
                1 for r in rows if r["closure_image_url"] and r["closure_audio_url"]
            ),
            "actions": actions,
            "closure_rate": round(closed * 100 / assigned) if assigned else 0,
            "avg_hours_to_assign": _avg_hours(rows, "created_at", "assigned_at"),
            "avg_hours_to_close": _avg_hours(rows, "assigned_at", "closed_at"),
        })

    unassigned = conn.execute(
        """SELECT COUNT(*) AS n FROM issues
            WHERE (assigned_coordinator IS NULL OR assigned_coordinator = '')
              AND status NOT IN ('CLOSED', 'FALSE')"""
    ).fetchone()["n"]
    return {"count": len(stats), "unassigned": unassigned, "coordinators": stats}


@router.post("/issues/{issue_id}/summarise-document")
def summarise_attached_document(
    issue_id: str,
    refresh: bool = Query(False),
    conn=Depends(get_db),
):
    """Read the citizen's attached petition and return a point-wise summary.

    Deliberately a manual action, not something the report path does: reading a
    document costs a model call, most grievances have no document, and an admin
    opening a ticket to glance at it should not trigger one. The result is
    cached on the row so the button is paid for once; `refresh=true` re-reads.
    """
    row = conn.execute(
        "SELECT document_url, document_name, document_summary FROM issues WHERE id = ?",
        (issue_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if not (row["document_url"] or "").strip():
        raise HTTPException(
            status_code=400, detail="This grievance has no attached document."
        )

    cached = (row["document_summary"] or "").strip()
    if cached and not refresh:
        try:
            return {**json.loads(cached), "cached": True}
        except ValueError:
            pass  # corrupt cache — fall through and re-read

    from gemini_service import summarise_document
    from utils import UPLOAD_DIR

    # document_url is "/uploads/documents/<file>"; map it back onto disk.
    rel = row["document_url"].replace("/uploads", "", 1).lstrip("/")
    path = os.path.join(UPLOAD_DIR, rel)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="The attached file is missing.")
    with open(path, "rb") as fh:
        data = fh.read()

    result = summarise_document(data, row["document_name"] or os.path.basename(path))
    if result.get("ok"):
        conn.execute(
            "UPDATE issues SET document_summary = ? WHERE id = ?",
            (json.dumps(result), issue_id),
        )
    return {**result, "cached": False}


# ── DESTRUCTIVE: reset to a clean slate for testing ────────────────────────
#
# Double-gated: the whole admin router already requires admin auth, AND this
# refuses unless ALLOW_DB_RESET is set on the environment. It wipes all
# user-generated data (grievances, accounts, coordinators, notifications) and
# every uploaded file, leaving an empty schema. It keeps the session signing
# key (app_secrets) and the department officer directory (dept_officers, which
# re-seeds on boot and is routing config, not test data). Admin sign-in is
# env-based, so it is unaffected.
_RESET_TABLES = [
    "issues", "users", "upvotes", "verifications", "coordinators",
    "otp_codes", "notifications", "device_tokens", "issue_events",
    "location_logs", "content_reports",
]


# ── Duplicates ───────────────────────────────────────────────────────────────
# Detection runs in the background half of a submission (routers/issues.py).
# Ruling on it is staff work, shared with the coordinator app through
# duplicates.py so the two consoles cannot decide the same case differently.


def _issue_or_404(conn, issue_id: str):
    row = duplicates.load(conn, issue_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    return row


@router.get("/issues/{issue_id}/duplicate")
def duplicate_context(issue_id: str, conn=Depends(get_db)):
    """What an admin needs to rule on a flagged grievance.

    ``parent`` is the suspected original; ``children`` are the reports already
    folded into THIS one, which is what the "also reported by" list on a
    surviving grievance is built from.
    """
    row = _issue_or_404(conn, issue_id)
    return {
        "awaiting_review": duplicates.awaiting_review(row),
        "decision": row["duplicate_decision"] or "",
        "decided_by": row["duplicate_decided_by"] or "",
        "merged_into_id": row["merged_into_id"],
        "parent": duplicates.parent_preview(conn, row),
        "children": duplicates.merged_children(conn, issue_id),
    }


@router.post("/issues/{issue_id}/merge")
def merge_duplicate(
    issue_id: str, parent_id: str = Form(...), conn=Depends(get_db)
):
    """Fold this grievance into the one it duplicates."""
    child = _issue_or_404(conn, issue_id)
    parent = _issue_or_404(conn, parent_id)
    return duplicates.merge(
        conn, child=child, parent=parent, actor_type="admin", actor_id="admin"
    )


@router.post("/issues/{issue_id}/keep-separate")
def keep_separate_duplicate(issue_id: str, conn=Depends(get_db)):
    """Rule that the flagged grievance is a different problem after all."""
    child = _issue_or_404(conn, issue_id)
    return duplicates.keep_separate(
        conn, child=child, actor_type="admin", actor_id="admin"
    )


@router.post("/issues/{issue_id}/unmerge")
def unmerge_duplicate(issue_id: str, conn=Depends(get_db)):
    """Reverse a merge — admin only, and the reason coordinators may merge.

    A merge folds away somebody's grievance, so the decision has to be
    recoverable by someone; otherwise a wrong call leaves the reporter
    following a stranger's ticket permanently.
    """
    child = _issue_or_404(conn, issue_id)
    return duplicates.unmerge(conn, child=child, actor_id="admin")


_AUDIO_MIME = {
    ".m4a": "audio/mp4", ".mp4": "audio/mp4", ".aac": "audio/aac",
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg",
    ".webm": "audio/webm",
}


@router.post("/issues/{issue_id}/reprocess")
def reprocess_issue(
    issue_id: str, background: BackgroundTasks, conn=Depends(get_db)
):
    """Retry the transcription/routing that failed on this grievance.

    The citizen is never told their submission half-failed — there is nothing
    they could do about it, and the grievance itself was saved. Instead the
    failure surfaces here, and this re-runs the same background work against
    the voice note already on disk.
    """
    row = _issue_or_404(conn, issue_id)
    audio_url = row["audio_url"] or ""
    audio_bytes = read_upload(audio_url)
    ext = os.path.splitext(audio_url)[1].lower()
    conn.execute(
        "UPDATE issues SET processing = 1, processing_error = '' WHERE id = ?",
        (issue_id,),
    )
    conn.commit()

    # A title somebody has since corrected by hand must survive the retry; the
    # placeholder the app sends when the citizen typed nothing must not.
    typed = (row["title"] or "").strip()
    keep_title = bool(typed) and typed != "Street Issue"

    from routers.issues import _finish_report

    background.add_task(
        _finish_report, issue_id=issue_id, audio_bytes=audio_bytes,
        audio_mime=_AUDIO_MIME.get(ext, "audio/mp4"),
        latitude=row["latitude"], longitude=row["longitude"],
        user_id=row["created_by"] or "", keep_title=keep_title,
    )
    return serialize_issue(duplicates.load(conn, issue_id))


@router.post("/reset-all")
def reset_all_data(conn=Depends(get_db)):
    if os.getenv("ALLOW_DB_RESET", "").strip().lower() not in ("1", "true", "yes"):
        raise HTTPException(
            status_code=403,
            detail="Reset is disabled. Set ALLOW_DB_RESET=1 on the backend to enable it.",
        )
    wiped = {}
    for table in _RESET_TABLES:
        try:
            n = conn.execute(f"SELECT COUNT(*) AS c FROM {table}").fetchone()["c"]
            conn.execute(f"DELETE FROM {table}")
            wiped[table] = n
        except Exception as exc:  # noqa: BLE001
            wiped[table] = f"skipped ({exc})"
    conn.commit()

    from utils import IMAGE_DIR, AUDIO_DIR, DOC_DIR, ensure_upload_dirs
    files_removed = 0
    for directory in (IMAGE_DIR, AUDIO_DIR, DOC_DIR):
        if os.path.isdir(directory):
            for name in os.listdir(directory):
                path = os.path.join(directory, name)
                try:
                    if os.path.isfile(path):
                        os.remove(path)
                        files_removed += 1
                except OSError:
                    pass
    ensure_upload_dirs()
    return {"ok": True, "wiped": wiped, "files_removed": files_removed}
