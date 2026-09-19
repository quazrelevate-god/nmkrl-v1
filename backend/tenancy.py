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
belongs to a tenant because its ward is in the tenant's constituency
(utils.CHENNAI_AC_MAP), and a coordinator because of their `constituency`.
Wards that CHENNAI_AC_MAP lists under two constituencies are visible to both
offices, which matches how those boundary wards are actually shared.
"""

from fastapi import Depends, Header, HTTPException

import admin_auth
from database import get_db
from utils import CHENNAI_AC_MAP


def decorate(row) -> dict:
    """A tenant row plus the ward list its constituency covers."""
    t = dict(row)
    t["wards"] = list(CHENNAI_AC_MAP.get(t["constituency"], []))
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
    if not tenant["wards"]:
        raise HTTPException(
            status_code=500,
            detail=f"This office's constituency '{tenant['constituency']}' is not recognised.",
        )
    return tenant


def ward_clause(tenant: dict, column: str = "ward_no") -> tuple[str, list]:
    """SQL fragment + params limiting `column` to the tenant's wards.

    ward_no is stored as an integer; CHENNAI_AC_MAP holds ward strings, so the
    comparison is done as text.
    """
    wards = tenant["wards"]
    placeholders = ",".join("?" for _ in wards)
    return f"CAST({column} AS TEXT) IN ({placeholders})", list(wards)


def owns_ward(tenant: dict, ward) -> bool:
    """Is this ward inside the tenant's constituency?"""
    return ward is not None and str(ward).strip() in tenant["wards"]


def load_issue(conn, issue_id: str, tenant: dict):
    """Fetch a grievance the tenant may act on, or 404.

    A grievance in another constituency answers exactly like one that does not
    exist, so an office can never confirm another office's grievance is there.
    """
    row = conn.execute("SELECT * FROM issues WHERE id = ?", (issue_id,)).fetchone()
    if row is None or not owns_ward(tenant, row["ward_no"]):
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
