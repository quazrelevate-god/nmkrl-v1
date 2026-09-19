"use client";

/**
 * Tickets — the staff portal's grievance queue.
 * Verified grievances (ACTIVE → CLOSED) shown in a reference-styled table with
 * status tabs, search, quick filters and ward / zone / constituency filtering.
 * Clicking a row opens the 70%-width TicketDrawer on the right.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Ticket as TicketIcon, Search, CalendarDays, CalendarRange, TimerOff,
  UserX, SlidersHorizontal, ChevronRight, X, Loader2,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import TicketDrawer from "@/components/admin/TicketDrawer";
import { fetchAdminIssues, fetchAdminIssueStats } from "@/lib/api";
import { departmentMeta } from "@/lib/departments";
import {
  TICKET_TABS, TICKET_STATUSES, portalStatus, derivePriority, PRIORITY_META,
  ticketNo, tokenNo, daysOpen, slaWeeksLabel, slaBreached, citizenName, initials,
} from "@/lib/adminModel";
import { CONSTITUENCIES, shortAC } from "@/lib/constituencies";

const PAGE_SIZE = 50; // server page size; "Load more" fetches the next page

const AVATAR_TINTS = ["bg-blue-100 text-blue-700", "bg-emerald-100 text-emerald-700",
  "bg-violet-100 text-violet-700", "bg-amber-100 text-amber-700", "bg-rose-100 text-rose-700"];
function tint(seed) {
  let h = 0; for (const c of seed || "x") h = (h * 31 + c.charCodeAt(0)) % AVATAR_TINTS.length;
  return AVATAR_TINTS[h];
}

export default function TicketsPage() {
  // boundaries + reload come from the shared provider; the ticket rows and
  // counts are now fetched server-side by this page (see below).
  // `issues` is the provider's FULL set (it is not paginated), so the drawer
  // can open a duplicate's original even when that ticket is not on the
  // page of rows currently loaded here.
  const { boundaries, reload, issues: allIssues } = useAdminData();
  const [tab, setTab] = useState("");
  const [query, setQuery] = useState("");
  const [quick, setQuick] = useState(null);           // today | week | sla | unassigned
  const [showFilters, setShowFilters] = useState(false);
  const [zone, setZone] = useState("");
  const [ward, setWard] = useState("");
  const [ac, setAc] = useState("");
  const [selected, setSelected] = useState(null);
  // Comparing a duplicate with its original and coming back.
  const [trail, setTrail] = useState([]);

  // Server-paged queue. The old page pulled every ticket and filtered / sorted /
  // counted it in the browser; now each filter change is a bounded query, the
  // tab counts come from a cheap SQL aggregate, and "Load more" pages the rest.
  const [rows, setRows] = useState([]);
  const [stats, setStats] = useState({ counts: {} });
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [total, setTotal] = useState(0);

  // Debounce search so typing doesn't fire a request per keystroke.
  const [debouncedQ, setDebouncedQ] = useState("");
  useEffect(() => {
    const t = setTimeout(() => setDebouncedQ(query.trim()), 300);
    return () => clearTimeout(t);
  }, [query]);

  const zoneOptions = useMemo(() => {
    const feats = boundaries?.zones?.features || [];
    return feats.map((f) => ({ zone: f.properties.zone, name: f.properties.zone_name }))
      .filter((z) => z.zone).sort((a, b) => Number(a.zone) - Number(b.zone));
  }, [boundaries]);

  const wardOptions = useMemo(() => {
    const feats = boundaries?.wards?.features || [];
    return feats.map((f) => ({ ward: f.properties.ward, zone: f.properties.zone }))
      .filter((w) => !zone || w.zone === zone).sort((a, b) => Number(a.ward) - Number(b.ward));
  }, [boundaries, zone]);

  // "today"/"this week" become a server-side created_at cutoff; "unassigned" a
  // server flag. "SLA breached" stays client-side — SLA is derived from the
  // routed department, which the server doesn't model — over the loaded rows.
  const since = useMemo(() => {
    if (quick === "today") { const d = new Date(); d.setHours(0, 0, 0, 0); return d.toISOString(); }
    if (quick === "week") return new Date(Date.now() - 7 * 86400000).toISOString();
    return undefined;
  }, [quick]);

  const filterParams = useMemo(() => ({
    zone: zone || undefined,
    ward: ward || undefined,
    constituency: ac || undefined,
    q: debouncedQ || undefined,
    unassigned: quick === "unassigned" || undefined,
    since,
  }), [zone, ward, ac, debouncedQ, quick, since]);

  const fetchPage = useCallback((offset) => fetchAdminIssues({
    ...filterParams,
    status: tab || undefined,
    board: !tab || undefined,          // "All" tab → board statuses only
    sort: "recent",
    limit: PAGE_SIZE,
    offset,
  }), [filterParams, tab]);

  // Re-run page 1 + counts on any filter/tab change.
  const key = JSON.stringify({ tab, ...filterParams });
  useEffect(() => {
    let alive = true;
    setLoading(true);
    Promise.all([fetchPage(0), fetchAdminIssueStats(filterParams)])
      .then(([page, st]) => {
        if (!alive) return;
        setRows(page.issues || []);
        setTotal(page.total ?? page.count ?? 0);
        setHasMore(!!page.has_more);
        setStats(st || { counts: {} });
      })
      .catch(() => { if (alive) { setRows([]); setTotal(0); setHasMore(false); } })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  async function loadMore() {
    setLoadingMore(true);
    try {
      const page = await fetchPage(rows.length);
      setRows((prev) => [...prev, ...(page.issues || [])]);
      setHasMore(!!page.has_more);
    } catch { /* keep what we have */ }
    finally { setLoadingMore(false); }
  }

  // After a drawer action: re-pull this view + counts, refresh the shared
  // provider (sidebar badges), and keep the drawer on the updated ticket.
  async function refresh(updated) {
    try {
      const [page, st] = await Promise.all([fetchPage(0), fetchAdminIssueStats(filterParams)]);
      setRows(page.issues || []);
      setTotal(page.total ?? page.count ?? 0);
      setHasMore(!!page.has_more);
      setStats(st || { counts: {} });
    } catch { /* ignore */ }
    reload?.();
    setSelected(updated || null);
  }

  // Tab counts from the server aggregate. "All" = every board status.
  const counts = useMemo(() => {
    const c = stats.counts || {};
    const out = { "": TICKET_STATUSES.reduce((s, k) => s + (c[k] || 0), 0) };
    for (const t of TICKET_TABS) if (t.match) out[t.key] = t.match.reduce((s, k) => s + (c[k] || 0), 0);
    return out;
  }, [stats]);

  // The one filter still applied in the browser (see `since`).
  const displayRows = useMemo(
    () => (quick === "sla" ? rows.filter(slaBreached) : rows),
    [rows, quick]
  );

  const activeFilters = [zone && `Zone ${zone}`, ward && `Ward ${ward}`, ac && shortAC(ac)].filter(Boolean);

  return (
    <>
      {/* Header */}
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand">
            <TicketIcon size={20} />
          </div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Tickets</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Manage and track citizen grievances</p>
          </div>
        </div>
        <span className="rounded-full bg-gradient-to-r from-brand to-brand-dark px-3 py-1 text-xs font-bold text-white">EN</span>
      </header>

      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-hidden px-7 py-5">
        {/* Search */}
        <div className="glass-panel flex items-center gap-2.5 rounded-2xl px-4 py-3">
          <Search size={18} className="text-slate-400" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search ticket #, name, mobile, headline…"
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400"
          />
          {query && <button onClick={() => setQuery("")}><X size={16} className="text-slate-400" /></button>}
        </div>

        {/* Tabs + quick filters */}
        <div className="glass-panel flex flex-wrap items-center gap-2 rounded-2xl px-3 py-2.5">
          <div className="flex flex-wrap items-center gap-1">
            {TICKET_TABS.map((t) => (
              <button
                key={t.key || "all"}
                onClick={() => setTab(t.key)}
                style={{ transition: "all .3s cubic-bezier(.22,1,.36,1)" }}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-semibold ${
                  tab === t.key ? "accent-ring bg-gradient-to-r from-brand to-brand-dark text-white" : "text-slate-500 hover:bg-white/50"
                }`}
              >
                {t.label}
                <span className={`rounded-md px-1.5 text-[11px] font-bold ${tab === t.key ? "bg-amber-400 text-brand-dark" : "bg-slate-100 text-slate-500"}`}>
                  {counts[t.key] ?? 0}
                </span>
              </button>
            ))}
          </div>
          <div className="ml-auto flex flex-wrap items-center gap-1.5">
            <QuickChip active={quick === "today"} onClick={() => setQuick(quick === "today" ? null : "today")} icon={CalendarDays}>Today</QuickChip>
            <QuickChip active={quick === "week"} onClick={() => setQuick(quick === "week" ? null : "week")} icon={CalendarRange}>This week</QuickChip>
            <QuickChip active={quick === "sla"} onClick={() => setQuick(quick === "sla" ? null : "sla")} icon={TimerOff}>SLA breached</QuickChip>
            <QuickChip active={quick === "unassigned"} onClick={() => setQuick(quick === "unassigned" ? null : "unassigned")} icon={UserX}>Unassigned</QuickChip>
            <QuickChip active={showFilters || activeFilters.length > 0} onClick={() => setShowFilters((s) => !s)} icon={SlidersHorizontal}>
              Filters{activeFilters.length > 0 ? ` · ${activeFilters.length}` : ""}
            </QuickChip>
          </div>

          {/* Geo filter row */}
          {showFilters && (
            <div className="mt-1 flex w-full flex-wrap items-center gap-2 border-t border-slate-100 pt-2.5">
              <select value={zone} onChange={(e) => { setZone(e.target.value); setWard(""); }} className={selectCls}>
                <option value="">All Zones</option>
                {zoneOptions.map((z) => <option key={z.zone} value={z.zone}>Zone {z.zone} · {z.name}</option>)}
              </select>
              <select value={ward} onChange={(e) => setWard(e.target.value)} className={selectCls}>
                <option value="">All Wards</option>
                {wardOptions.map((w) => <option key={w.ward} value={w.ward}>Ward {w.ward}</option>)}
              </select>
              <select value={ac} onChange={(e) => setAc(e.target.value)} className={selectCls}>
                <option value="">All Constituencies</option>
                {CONSTITUENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
              {activeFilters.length > 0 && (
                <button onClick={() => { setZone(""); setWard(""); setAc(""); }} className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-blue-600 hover:bg-blue-50">
                  Clear geo filters
                </button>
              )}
            </div>
          )}
        </div>

        {/* Table */}
        <div className="glass-panel-strong min-h-0 flex-1 flex flex-col overflow-auto rounded-2xl">
          <table className="w-full shrink-0 border-collapse text-sm">
            <thead className="sticky top-0 z-10 bg-white/70 text-left text-[11px] font-bold uppercase tracking-wider text-slate-400 backdrop-blur">
              <tr>
                <th className="px-5 py-3">Ticket</th>
                <th className="px-3 py-3">Citizen</th>
                <th className="px-3 py-3">Summary</th>
                <th className="px-3 py-3">Department</th>
                <th className="px-3 py-3">Priority</th>
                <th className="px-3 py-3">Status</th>
                <th className="px-3 py-3">Assigned</th>
                <th className="px-3 py-3 text-right">Open For</th>
                <th className="w-8" />
              </tr>
            </thead>
            <tbody className="bg-white">
              {loading ? (
                <tr><td colSpan={9} className="px-5 py-16 text-center text-slate-400">Loading tickets…</td></tr>
              ) : displayRows.length === 0 ? (
                <tr><td colSpan={9} className="px-5 py-16 text-center text-slate-400">No tickets match this view.</td></tr>
              ) : displayRows.map((issue) => (
                <TicketRow key={issue.id} issue={issue} onOpen={() => setSelected(issue)} />
              ))}
            </tbody>
          </table>
          {/* Solid white under the rows. The panel stays glass so the sticky header keeps
             its translucency; the rows are painted white instead, and this filler whitens
             any space a short list leaves below them, whatever height the header renders at. */}
          <div aria-hidden className="flex-1 bg-white" />
          {!loading && (hasMore || rows.length > 0) && (
            <div className="border-t border-slate-200/50 bg-white px-5 py-3 text-center">
              {hasMore ? (
                <button
                  onClick={loadMore}
                  disabled={loadingMore}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-slate-100 px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-200 disabled:opacity-60"
                >
                  {loadingMore ? <><Loader2 size={13} className="animate-spin" /> Loading…</> : `Load more · ${rows.length} of ${total}`}
                </button>
              ) : (
                <p className="text-xs text-slate-400">{total} ticket{total === 1 ? "" : "s"}{quick === "sla" ? ` · ${displayRows.length} breaching SLA` : ""}</p>
              )}
            </div>
          )}
        </div>
      </div>

      {selected && (
        <TicketDrawer
          issue={selected}
          onClose={() => { setSelected(null); setTrail([]); }}
          // A duplicate ruling reports `null`, meaning "stay on this grievance
          // so the admin sees the outcome" — refresh() alone would read that
          // as "close the drawer". Every other action passes the updated row.
          onChanged={(updated) => refresh(updated === null ? selected : updated)}
          onOpenIssue={(id) => {
            const next = rows.find((i) => i.id === id)
              || (allIssues || []).find((i) => i.id === id);
            if (!next) return;
            setTrail((t) => [...t, selected]);
            setSelected(next);
          }}
          onBack={trail.length ? () => {
            setSelected(trail[trail.length - 1]);
            setTrail((t) => t.slice(0, -1));
          } : null}
        />
      )}
    </>
  );
}

const selectCls = "rounded-lg border border-white/60 bg-white/60 px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none backdrop-blur focus:border-brand";

function QuickChip({ active, onClick, icon: Icon, children }) {
  return (
    <button
      onClick={onClick}
      style={{ transition: "all .3s cubic-bezier(.22,1,.36,1)" }}
      className={`flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold ${
        active ? "border-brand/40 bg-brand-50 text-brand" : "border-white/60 bg-white/40 text-slate-500 hover:bg-white/70"
      }`}
    >
      <Icon size={13} /> {children}
    </button>
  );
}

function TicketRow({ issue, onOpen }) {
  const st = portalStatus(issue.status);
  const priority = derivePriority(issue);
  const pm = PRIORITY_META[priority];
  const dept = departmentMeta(issue.department);
  const name = citizenName(issue);
  const d = daysOpen(issue);
  const breached = slaBreached(issue);

  return (
    <tr onClick={onOpen} style={{ transition: "background .25s ease" }} className="group cursor-pointer border-t border-slate-200/50 hover:bg-slate-50">
      {/* Ticket + priority accent */}
      <td className="relative px-5 py-3.5">
        <span className="absolute inset-y-2 left-0 w-1 rounded-full" style={{ background: pm.dot }} />
        <p className="font-bold text-brand">{ticketNo(issue)}</p>
        <p className="text-[11px] text-slate-400">{tokenNo(issue)}</p>
      </td>
      {/* Citizen */}
      <td className="px-3 py-3.5">
        <div className="flex items-center gap-2.5">
          <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold ${tint(name)}`}>
            {initials(name)}
          </span>
          <div className="min-w-0">
            <p className="truncate font-bold text-slate-800">{name}</p>
            {issue.phone && <p className="text-[11px] text-slate-400">+91 {issue.phone}</p>}
          </div>
        </div>
      </td>
      {/* Summary */}
      <td className="max-w-[280px] px-3 py-3.5">
        <p className="line-clamp-2 text-slate-700">{issue.title || <span className="italic text-slate-400">No headline</span>}</p>
      </td>
      {/* Department */}
      <td className="max-w-[190px] px-3 py-3.5">
        {issue.department ? <p className="line-clamp-2 text-[13px] text-slate-600">{dept.short}</p> : <span className="text-slate-300">—</span>}
      </td>
      {/* Priority */}
      <td className="px-3 py-3.5">
        <span className={`inline-flex rounded-md px-2 py-1 text-[11px] font-bold ${pm.badge}`}>{priority}</span>
      </td>
      {/* Status */}
      <td className="px-3 py-3.5">
        <span className={`inline-flex rounded-full px-2.5 py-1 text-[11px] font-bold ${st.badge}`}>{st.label}</span>
      </td>
      {/* Assigned */}
      <td className="px-3 py-3.5">
        {issue.assigned_coordinator
          ? <span className="text-[13px] font-semibold text-slate-700">@{issue.assigned_coordinator}</span>
          : <span className="text-[13px] italic text-slate-400">Unassigned</span>}
      </td>
      {/* Open for */}
      <td className="px-3 py-3.5 text-right">
        <p className={`text-[13px] font-bold ${breached ? "text-red-500" : "text-emerald-600"}`}>{d}d</p>
        <p className="text-[10px] text-slate-400">{slaWeeksLabel(issue)}</p>
      </td>
      <td className="pr-4 text-slate-300 group-hover:text-brand"><ChevronRight size={18} /></td>
    </tr>
  );
}
