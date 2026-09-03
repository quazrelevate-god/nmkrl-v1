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
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

import audit
from database import get_db
from utils import CHENNAI_AC_MAP, now_iso, serialize_issue

router = APIRouter(prefix="/api/admin", tags=["admin"])

VALID_STATUSES = {
    "SUBMITTED", "ACTIVE", "FORWARDED", "IN_PROGRESS",
    "PENDING_VERIFICATION", "CLOSED", "FALSE",
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

    sql = "SELECT * FROM issues"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    rows = conn.execute(sql, params).fetchall()

    issues = [serialize_issue(r) for r in rows]

    if sort == "recent":
        issues.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    else:
        issues.sort(key=lambda x: (-x.get("upvotes", 0), x.get("created_at", "")))

    return {"count": len(issues), "issues": issues}


@router.get("/users")
def list_users(q: str = Query(None), conn=Depends(get_db)):
    """
    List citizen accounts with per-user grievance counters, so the admin console
    can show real 'user related data' (who reported, how much, how much resolved).

    Counters are computed from the issues table keyed on issues.created_by = users.id:
      - reports:  total grievances submitted
      - resolved: grievances now CLOSED
      - open:     grievances not yet CLOSED/FALSE
    Optional q filters by name or phone.
    """
    clauses, params = [], []
    if q:
        needle = f"%{q.strip().lower()}%"
        clauses.append("(LOWER(name) LIKE ? OR phone LIKE ?)")
        params.extend([needle, needle])
    sql = "SELECT id, name, phone, created_at FROM users"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY created_at DESC"
    users = [dict(r) for r in conn.execute(sql, params).fetchall()]

    # Aggregate grievance counts per user in one pass.
    agg = {}
    for row in conn.execute(
        """SELECT created_by,
                  COUNT(*) AS reports,
                  SUM(CASE WHEN status = 'CLOSED' THEN 1 ELSE 0 END) AS resolved,
                  SUM(CASE WHEN status NOT IN ('CLOSED','FALSE') THEN 1 ELSE 0 END) AS open
             FROM issues
            WHERE created_by IS NOT NULL AND created_by != ''
         GROUP BY created_by"""
    ).fetchall():
        agg[row["created_by"]] = {
            "reports": row["reports"] or 0,
            "resolved": row["resolved"] or 0,
            "open": row["open"] or 0,
        }

    for u in users:
        stats = agg.get(u["id"], {"reports": 0, "resolved": 0, "open": 0})
        u.update(stats)

    return {"count": len(users), "users": users}


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
    conn.execute("UPDATE issues SET status = 'FORWARDED' WHERE id = ?", (issue_id,))
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    return serialize_issue(row)


@router.post("/issues/{issue_id}/close")
def close_issue(issue_id: str, conn=Depends(get_db)):
    issue = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if issue is None:
        raise HTTPException(status_code=404, detail="Issue not found")
    if issue["status"] not in ("ACTIVE", "FORWARDED", "IN_PROGRESS"):
        raise HTTPException(
            status_code=409,
            detail=f"Only open issues can be resolved (status={issue['status']})",
        )
    conn.execute(
        "UPDATE issues SET status = 'PENDING_VERIFICATION', notify_reporter = 1 WHERE id = ?",
        (issue_id,),
    )
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
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
             FROM coordinators ORDER BY name COLLATE NOCASE"""
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
