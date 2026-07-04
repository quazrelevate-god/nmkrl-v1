"use client";

/**
 * AdminDataProvider
 * -----------------
 * Loads the full issue set + GCC boundaries once and shares them across every
 * admin page (Tickets, Petition Review, Performance) and the sidebar badges,
 * so navigating between them is instant and counts stay in sync. `reload()`
 * refreshes after any status mutation (verify / forward / resolve …).
 */

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { fetchAdminIssues, fetchBoundaries } from "@/lib/api";
import { TICKET_STATUSES } from "@/lib/adminModel";

const AdminDataContext = createContext(null);

export function AdminDataProvider({ children }) {
  const [issues, setIssues] = useState([]);
  const [boundaries, setBoundaries] = useState(null);
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
  useEffect(() => { fetchBoundaries().then(setBoundaries).catch(() => {}); }, []);

  // Split the two worlds: petition review (unverified) vs tickets (verified).
  const pending = issues.filter((i) => i.status === "SUBMITTED");
  const tickets = issues.filter((i) => TICKET_STATUSES.includes(i.status));

  const value = { issues, tickets, pending, boundaries, loading, error, reload };
  return <AdminDataContext.Provider value={value}>{children}</AdminDataContext.Provider>;
}

export function useAdminData() {
  const ctx = useContext(AdminDataContext);
  if (!ctx) throw new Error("useAdminData must be used within AdminDataProvider");
  return ctx;
}
