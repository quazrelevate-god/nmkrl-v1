"""
duplicates.py
-------------
Ruling on a suspected duplicate, and folding one grievance into another.

DETECTION is not here — it stays in the background half of a submission
(``routers/issues.py``), where Gemini (or, with no key, a same-ward proximity
rule) sets ``possible_duplicate_id``. What lives here is the RULING, which is
staff work: admin and the ward coordinator both see the flagged grievance and
either merge it into the one reported first, or keep the two separate.

The reporter used to be asked instead, via "submit anyway / withdraw". That
either erased the flag or hard-deleted the report, so nobody downstream ever
saw a duplicate — and it asked a citizen to judge whether someone else's
grievance was the same as theirs, which they cannot know.

Both consoles call these functions rather than writing the UPDATE themselves,
so the two cannot drift apart the way the two copies of the false-petition
reason list already did.

Vocabulary
    parent  the grievance reported FIRST — the one that survives
    child   the later report that duplicates it

A merge keeps the child row. Its photo, voice note and reporter are the
evidence that several people reported the same problem, and the parent's
detail view lists them. Only its place in the queues goes away.
"""

from fastapi import HTTPException

import audit
from utils import haversine_m, new_id, now_iso, public_issue, serialize_issue

#: Status a child takes once folded into its parent. It is deliberately not
#: FALSE — that reads to the citizen as "your report was a fabrication" — and
#: not a closed state either, because the problem is still open, just counted
#: once. Keeping it out of the open set also stops a merged child ever being
#: offered as a duplicate candidate for the next report.
MERGED = "MERGED"

#: Outcomes a grievance cannot be merged away from — the citizen has already
#: been told how it ended, and the closure evidence belongs to that ticket.
_SETTLED = frozenset({"CLOSED", "RESOLVED", "FALSE", MERGED})


def load(conn, issue_id: str):
    """Fetch one grievance row, or None."""
    return conn.execute(
        "SELECT * FROM issues WHERE id = ?", (issue_id,)
    ).fetchone()


def awaiting_review(row) -> bool:
    """True when detection flagged this and nobody has ruled on it yet."""
    if row is None:
        return False
    return bool(row["possible_duplicate_id"]) and not (
        row["duplicate_decision"] or ""
    )


def _root(conn, row, _hops: int = 0):
    """Follow merged_into_id to the grievance that actually survives.

    Merging into something already merged would build a chain, and every
    reader would then have to walk it. Resolving to the root keeps the shape
    flat: a parent with children, never a parent with grandchildren. The hop
    limit is paranoia against a cycle produced by a bad row.
    """
    parent_id = row["merged_into_id"] if "merged_into_id" in row.keys() else None
    if not parent_id or _hops >= 10:
        return row
    nxt = load(conn, parent_id)
    return row if nxt is None else _root(conn, nxt, _hops + 1)


def _previous_status(conn, issue_id: str) -> str:
    """What the child's status was before it was merged.

    Read back off the merge event rather than stored in its own column — the
    timeline already records from_status for every action, so an unmerge can
    put the grievance back exactly where it was.
    """
    row = conn.execute(
        """SELECT from_status FROM issue_events
            WHERE issue_id = ? AND action = 'merge'
         ORDER BY created_at DESC LIMIT 1""",
        (issue_id,),
    ).fetchone()
    return (row["from_status"] if row else "") or "SUBMITTED"


def _sync_support(conn, issue_id: str) -> None:
    """Make the counter agree with the rows behind it.

    ``issues.upvotes`` is denormalised, and _reconcile_upvotes() on boot will
    reconcile any disagreement — so a merge that only incremented the counter
    would be silently undone. Write the row, then set the counter to the row
    count, and the two can never drift.
    """
    conn.execute(
        """UPDATE issues
              SET upvotes = (SELECT COUNT(*) FROM upvotes WHERE issue_id = ?)
            WHERE id = ?""",
        (issue_id, issue_id),
    )


def parent_preview(conn, child) -> dict | None:
    """The suspected original, safe to show whoever is reviewing the child.

    Deliberately PII-stripped. A coordinator reviewing a duplicate often has
    no claim on the parent at all — it can sit in a neighbouring ward, or
    belong to another coordinator — so they get what they need to judge
    sameness (ticket, title, photo, distance, support) and nothing about the
    person who reported it.
    """
    parent_id = child["possible_duplicate_id"] or child["merged_into_id"]
    if not parent_id:
        return None
    parent = load(conn, parent_id)
    if parent is None:
        return None
    data = public_issue(parent)
    data["distance_m"] = round(
        haversine_m(
            child["latitude"], child["longitude"],
            parent["latitude"], parent["longitude"],
        ),
        1,
    )
    data["same_ward"] = parent["ward_no"] == child["ward_no"]
    return data


def merged_children(conn, parent_id: str, *, redact: bool = False) -> list[dict]:
    """Every report folded into this one — the "also reported by" list.

    Knowing that four different people reported the same broken streetlight is
    the whole point, so for whoever owns the grievance this keeps the
    reporters' details. Pass ``redact`` for a viewer with no claim on it — a
    coordinator comparing against a parent in a neighbouring ward — and they
    get the reports without the people behind them.
    """
    rows = conn.execute(
        """SELECT * FROM issues
            WHERE merged_into_id = ?
         ORDER BY merged_at ASC""",
        (parent_id,),
    ).fetchall()
    shape = public_issue if redact else serialize_issue
    return [shape(r) for r in rows]


def merge(conn, *, child, parent, actor_type: str, actor_id: str) -> dict:
    """Fold [child] into [parent]. Returns the updated child.

    Raises 4xx when the pair cannot legally be merged. First ruling wins: a
    grievance somebody already decided on is refused rather than quietly
    re-decided, so admin and a coordinator acting at the same moment cannot
    produce two different outcomes.
    """
    if child["duplicate_decision"]:
        raise HTTPException(
            status_code=409,
            detail="This grievance has already been reviewed.",
        )
    parent = _root(conn, parent)
    if parent["id"] == child["id"]:
        raise HTTPException(
            status_code=400, detail="A grievance cannot be merged into itself."
        )
    if parent["status"] == MERGED:
        raise HTTPException(
            status_code=409,
            detail="That grievance has itself been merged into another.",
        )
    # Different corporations are different offices' cases, even a street apart.
    if (parent["corporation"] or "chennai") != (child["corporation"] or "chennai"):
        raise HTTPException(
            status_code=409,
            detail="These grievances are in different corporations and cannot be merged.",
        )
    # Folding away a grievance that already reached an outcome would rewrite
    # a settled record — the citizen was told it was resolved or rejected, and
    # the closure evidence belongs to that ticket. Detection only ever flags
    # fresh reports; this guards the by-hand path.
    if child["status"] in _SETTLED:
        raise HTTPException(
            status_code=409,
            detail=(
                "This grievance is already "
                f"{child['status'].lower().replace('_', ' ')} and cannot be merged."
            ),
        )

    now = now_iso()
    was = child["status"]

    conn.execute(
        """UPDATE issues
              SET merged_into_id = ?, merged_at = ?, status = ?,
                  duplicate_decision = 'merged', duplicate_decided_by = ?,
                  possible_duplicate_id = ?
            WHERE id = ?""",
        (parent["id"], now, MERGED, actor_id, parent["id"], child["id"]),
    )

    # Anything already merged into the child comes along, so no report is left
    # pointing at a grievance that is no longer the survivor.
    conn.execute(
        "UPDATE issues SET merged_into_id = ? WHERE merged_into_id = ?",
        (parent["id"], child["id"]),
    )

    # The reporter's support moves to the parent. ON CONFLICT DO NOTHING because
    # they may already have upvoted it — UNIQUE(user_id, issue_id) — and one
    # person must never count twice.
    if child["created_by"]:
        conn.execute(
            """INSERT INTO upvotes (id, user_id, issue_id, name)
               VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING""",
            (new_id(), child["created_by"], parent["id"], child["name"] or ""),
        )
    _sync_support(conn, parent["id"])

    note = f"Merged into {parent['ticket_number'] or parent['id']}."
    audit.record(
        conn, child["id"], action="merge", actor_type=actor_type,
        actor_id=actor_id, from_status=was, to_status=MERGED, note=note,
    )
    audit.record(
        conn, parent["id"], action="merge_received", actor_type=actor_type,
        actor_id=actor_id, from_status=parent["status"],
        to_status=parent["status"],
        note=f"Absorbed duplicate {child['ticket_number'] or child['id']}.",
    )

    updated = load(conn, child["id"])
    _notify_merged(conn, updated, load(conn, parent["id"]), actor_id)
    return serialize_issue(updated)


def keep_separate(conn, *, child, actor_type: str, actor_id: str) -> dict:
    """Rule that the flagged grievance is its own problem after all."""
    if child["duplicate_decision"]:
        raise HTTPException(
            status_code=409,
            detail="This grievance has already been reviewed.",
        )
    conn.execute(
        """UPDATE issues
              SET duplicate_decision = 'separate', duplicate_decided_by = ?
            WHERE id = ?""",
        (actor_id, child["id"]),
    )
    audit.record(
        conn, child["id"], action="duplicate_separate", actor_type=actor_type,
        actor_id=actor_id, from_status=child["status"],
        to_status=child["status"],
        note="Reviewed as a separate grievance, not a duplicate.",
    )
    return serialize_issue(load(conn, child["id"]))


def unmerge(conn, *, child, actor_id: str) -> dict:
    """Undo a merge, putting the child back as its own grievance.

    Admin-only. A merge folds away somebody's grievance, so a wrong one has to
    be reversible — otherwise the reporter is left following a stranger's
    ticket with no way back.
    """
    parent_id = child["merged_into_id"]
    if not parent_id:
        raise HTTPException(
            status_code=409, detail="This grievance is not merged."
        )
    restored = _previous_status(conn, child["id"])
    conn.execute(
        """UPDATE issues
              SET merged_into_id = NULL, merged_at = NULL, status = ?,
                  duplicate_decision = '', duplicate_decided_by = ?
            WHERE id = ?""",
        (restored, actor_id, child["id"]),
    )
    # Take back the support that moved across, unless they had also supported
    # the parent on their own before the merge — which we cannot distinguish,
    # so the reporter's own vote is the only one withdrawn.
    if child["created_by"]:
        conn.execute(
            "DELETE FROM upvotes WHERE issue_id = ? AND user_id = ?",
            (parent_id, child["created_by"]),
        )
    _sync_support(conn, parent_id)
    audit.record(
        conn, child["id"], action="unmerge", actor_type="admin",
        actor_id=actor_id, from_status=MERGED, to_status=restored,
        note="Merge reversed; restored as its own grievance.",
    )
    return serialize_issue(load(conn, child["id"]))


def _notify_merged(conn, child, parent, actor_id: str) -> None:
    """Tell the reporter, and the coordinator who owns the surviving ticket.

    Best-effort: a notification that cannot be delivered must never roll back
    a merge that has already been decided.
    """
    try:
        from routers.notifications import emit_merged_into_parent

        emit_merged_into_parent(conn, child, parent)
    except Exception:
        pass
    # The parent can belong to another ward or another coordinator — merging
    # hands them a report they never saw arrive, so say so.
    try:
        owner = (parent["assigned_coordinator"] or "").strip().lower()
        if owner and owner != (actor_id or "").strip().lower():
            from routers.notifications import emit_to_coordinator

            emit_to_coordinator(
                conn, parent, "merge_received",
                "Another report of this problem was merged in. "
                f"It now has {parent['upvotes']} people behind it.",
            )
    except Exception:
        pass
