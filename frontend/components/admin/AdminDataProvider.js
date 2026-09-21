"use client";

/**
 * AdminDataProvider
 * -----------------
 * Loads the office's issue set + boundaries once and shares them across every
 * admin page (Tickets, Petition Review, Performance) and the sidebar badges,
 * so navigating between them is instant and counts stay in sync. `reload()`
 * refreshes after any status mutation (verify / forward / resolve …).
 *
 * Tenant scoping: the console belongs to ONE MLA office (tenant), bound to one
 * constituency in one corporation. The server already limits every grievance
 * to that constituency; here the corporation's boundaries are narrowed to the
 * office's own wards
 * and zones too, so no ward picker, zone picker or map ever offers a place
 * outside it. `boundaries` stays null until the tenant is known, so a picker
 * never flashes the whole city first.
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { fetchAdminIssues, fetchAdminTenant, fetchBoundaries } from "@/lib/api";
import { TICKET_STATUSES } from "@/lib/adminModel";

const AdminDataContext = createContext(null);

export function AdminDataProvider({ children }) {
  const [issues, setIssues] = useState([]);
  const [rawBoundaries, setRawBoundaries] = useState(null);
  const [tenant, setTenant] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const reload = useCallback(async () => {
    try {
      const data = await fetchAdminIssues({ sort: "recent" });
      setIssues(data.issues || []);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { reload(); }, [reload]);
  useEffect(() => { fetchAdminTenant().then(setTenant).catch(() => {}); }, []);
  // The office's own corporation's map (Tambaram or Chennai — see the sidebar
  // toggle), fetched once the office is known.
  const corporation = tenant?.corporation;
  useEffect(() => {
    if (!corporation) return;
    fetchBoundaries(corporation).then(setRawBoundaries).catch(() => {});
  }, [corporation]);

  // Boundaries narrowed to this office's constituency.
  const boundaries = useMemo(() => {
    if (!rawBoundaries || !tenant) return null;
    const wardSet = new Set((tenant.wards || []).map(String));
    const zoneSet = new Set((tenant.zones || []).map((z) => String(z.zone)));
    const keep = (fc, test) => ({ ...(fc || {}), features: ((fc && fc.features) || []).filter(test) });
    return {
      ...rawBoundaries,
      wards: keep(rawBoundaries.wards, (f) => wardSet.has(String(f.properties?.ward))),
      zones: keep(rawBoundaries.zones, (f) => zoneSet.has(String(f.properties?.zone))),
    };
  }, [rawBoundaries, tenant]);

  // Split the two worlds: petition review (unverified) vs tickets (verified).
  const pending = issues.filter((i) => i.status === "SUBMITTED");
  const tickets = issues.filter((i) => TICKET_STATUSES.includes(i.status));

  const value = { issues, tickets, pending, boundaries, tenant, loading, error, reload };
  return <AdminDataContext.Provider value={value}>{children}</AdminDataContext.Provider>;
}

export function useAdminData() {
  const ctx = useContext(AdminDataContext);
  if (!ctx) throw new Error("useAdminData must be used within AdminDataProvider");
  return ctx;
}
