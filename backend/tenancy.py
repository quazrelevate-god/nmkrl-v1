"""
tenancy.py
----------
Tenant resolution and scoping for the MLA-office console.

Each MLA office is a tenant bound to one Assembly Constituency, and its staff
must only ever see that constituency: its wards, the grievances in them, and its
coordinators. This module is the one place that rule lives — every admin
endpoint depends on `current_tenant` and filters through the helpers below —
so a new endpoint cannot quietly forget it.

Tenancy is derived from geography rather than stored on every row: a grievance
belongs to a tenant because its ward is in the tenant's constituency, and a
coordinator because of their `constituency`. Constituencies belong to a
corporation (corporations.py), and ward numbers repeat across corporations, so
a grievance must also be in the tenant's corporation (issues.corporation).
Wards that an AC map lists under two constituencies are visible to both
offices, which matches how those boundary wards are actually shared.

Only the active corporation's offices can use the console: switching the
corporation sends sessions of the other corporation's offices back to sign in.
"""

from fastapi import Depends, Header, HTTPException

import admin_auth
import corporations
from database import get_db


def decorate(row) -> dict:
    """A tenant row plus its corporation and the ward list its constituency covers."""
    t = dict(row)
    cid = corporations.corporation_of_constituency(t["constituency"])
    t["corporation"] = cid
    corp = corporations.CORPORATIONS.get(cid)
    t["corporation_name"] = corp["name"] if corp else None
    t["corporation_short"] = corp["short_name"] if corp else None
    t["wards"] = list(corp["ac_map"].get(t["constituency"], [])) if corp else []
    return t


def current_tenant(
    x_admin_token: str = Header(default=""),
    authorization: str = Header(default=""),
    conn=Depends(get_db),
) -> dict:
    """FastAPI dependency: the tenant the signed-in operator works for.

    The tenant id travels inside the signed admin token, so it cannot be swapped
    for another office's. A token minted before tenancy existed carries none and
    is sent back to sign in; a suspended office is refused outright.
    """
    data = admin_auth.decode_request(x_admin_token, authorization)
    tenant_id = data.get("t")
    row = (
        conn.execute("SELECT * FROM tenants WHERE id = ?", (tenant_id,)).fetchone()
        if tenant_id else None
    )
    if row is None:
        raise HTTPException(
            status_code=401,
            detail="Your session is not linked to an MLA office. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if (row["status"] or "active").lower() != "active":
        raise HTTPException(status_code=403, detail="This MLA office account is suspended.")
    tenant = decorate(row)
    active = corporations.active_id(conn)
    if tenant["corporation"] and tenant["corporation"] != active:
        raise HTTPException(
            status_code=401,
            detail=(f"The console was switched to {corporations.get(active)['short_name']}. "
                    "Please sign in again."),
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not tenant["wards"]:
        raise HTTPException(
            status_code=500,
            detail=f"This office's constituency '{tenant['constituency']}' is not recognised.",
        )
    return tenant


def ward_clause(tenant: dict, column: str = "ward_no") -> tuple[str, list]:
    """SQL fragment + params limiting `column` to the tenant's wards.

    Also limits the grievance to the tenant's corporation, whose column sits
    beside `column` (same table alias). ward_no is stored as an integer and the
    AC maps hold ward strings, so the comparison is done as text.
    """
    wards = tenant["wards"]
    placeholders = ",".join("?" for _ in wards)
    prefix = column.rsplit(".", 1)[0] + "." if "." in column else ""
    return (
        f"(CAST({column} AS TEXT) IN ({placeholders}) AND {prefix}corporation = ?)",
        [*wards, tenant["corporation"]],
    )


def owns_ward(tenant: dict, ward, corporation: str | None = None) -> bool:
    """Is this ward inside the tenant's constituency?

    Pass the grievance's `corporation` when checking a grievance: ward numbers
    repeat across corporations. Without it the ward is taken to be in the
    tenant's own corporation (a ward the office is choosing).
    """
    if corporation is not None and corporation != tenant["corporation"]:
        return False
    return ward is not None and str(ward).strip() in tenant["wards"]


def owns_issue(tenant: dict, issue) -> bool:
    """Is this grievance (row or dict) the tenant's to see and act on?"""
    return owns_ward(tenant, issue["ward_no"], issue["corporation"] or corporations.LEGACY_CORPORATION)


def load_issue(conn, issue_id: str, tenant: dict):
    """Fetch a grievance the tenant may act on, or 404.

    A grievance in another constituency answers exactly like one that does not
    exist, so an office can never confirm another office's grievance is there.
    """
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if row is None or not owns_issue(tenant, row):
        raise HTTPException(status_code=404, detail="Issue not found")
    return row


def load_coordinator(conn, username: str, tenant: dict):
    """Fetch one of the tenant's coordinators by username, or None.

    Coordinators belong to a constituency; one from another office is treated as
    unknown here.
    """
    return conn.execute(
        "SELECT * FROM coordinators WHERE LOWER(username) = ? AND constituency = ?",
        ((username or "").strip().lower(), tenant["constituency"]),
    ).fetchone()
