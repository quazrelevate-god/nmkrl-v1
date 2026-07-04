"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  ArrowLeft, ThumbsUp, CheckCircle2, Clock, PlayCircle, ShieldCheck,
  Phone, Filter, ArrowUpDown, MapPin, Flame, BarChart3, LayoutGrid,
  ChevronRight, ChevronDown, Building2, Send,
} from "lucide-react";
import {
  fetchAdminIssues, fetchBoundaries, adminVerifyGrievance, adminCloseIssue, adminStartIssue, mediaUrl,
} from "@/lib/api";
import { statusMeta } from "@/lib/status";
import { ticketNumber } from "@/lib/ticket";
import { departmentMeta } from "@/lib/departments";
import WhatsAppModal from "@/components/WhatsAppModal";

const MiniMap = dynamic(() => import("@/components/MiniMap"), { ssr: false });
const AdminHeatMap = dynamic(() => import("@/components/AdminHeatMap"), {
  ssr: false,
  loading: () => <div className="flex h-full items-center justify-center text-sm text-slate-400">Loading map…</div>,
});

const FILTERS = [
  { key: "",                     label: "All" },
  { key: "SUBMITTED",            label: "Pending Verification" },
  { key: "ACTIVE",               label: "Assigned" },
  { key: "IN_PROGRESS",          label: "In Progress" },
  { key: "PENDING_VERIFICATION", label: "Citizen Verify" },
  { key: "CLOSED",               label: "Completed" },
];

const SORTS = [
  { key: "upvotes", label: "Most Upvoted" },
  { key: "recent",  label: "Most Recent" },
];

const VIEWS = [
  { key: "complaints", label: "Complaint Density", icon: Flame },
  { key: "upvotes",    label: "Upvote Hotspots",   icon: BarChart3 },
  { key: "overview",   label: "All-in-One",        icon: LayoutGrid },
];

const FUNNEL = [
  { label: "Assigned",     match: ["ACTIVE", "IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED"] },
  { label: "Inspection",   match: ["IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED"] },
  { label: "Repair",       match: ["IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED"] },
  { label: "Verification", match: ["PENDING_VERIFICATION", "CLOSED"] },
  { label: "Completed",    match: ["CLOSED"] },
];

export default function AdminScreen() {
  const [issues, setIssues]       = useState([]);   // full set (all statuses)
  const [loading, setLoading]     = useState(true);
  const [busyId, setBusyId]       = useState(null);
  const [error, setError]         = useState(null);
  const [statusFilter, setStatusFilter] = useState("");
  const [zoneFilter, setZoneFilter] = useState("");
  const [wardFilter, setWardFilter] = useState("");
  const [sortBy, setSortBy]       = useState("upvotes");
  const [view, setView]           = useState("complaints");
  const [expandedId, setExpandedId] = useState(null);
  const [boundaries, setBoundaries] = useState(null);
  const [waTarget, setWaTarget]   = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchAdminIssues({ sort: sortBy }); // no status -> all
      setIssues(data.issues || []);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [sortBy]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { fetchBoundaries().then(setBoundaries).catch(() => {}); }, []);

  async function act(fn, id) {
    setBusyId(id);
    try { await fn(id); await load(); }
    catch (err) { setError(err.message); }
    finally { setBusyId(null); }
  }

  // Zone options (roman + name) from the boundary data, sorted by ward count desc.
  const zoneOptions = useMemo(() => {
    const feats = boundaries?.zones?.features || [];
    return feats
      .map(f => ({ zone: f.properties.zone, name: f.properties.zone_name }))
      .filter(z => z.zone)
      .sort((a, b) => Number(a.zone) - Number(b.zone));
  }, [boundaries]);

  // Ward options — constrained to the selected zone when one is active.
  const wardOptions = useMemo(() => {
    const feats = boundaries?.wards?.features || [];
    return feats
      .map(f => ({ ward: f.properties.ward, zone: f.properties.zone }))
      .filter(w => !zoneFilter || w.zone === zoneFilter)
      .sort((a, b) => Number(a.ward) - Number(b.ward));
  }, [boundaries, zoneFilter]);

  // Zone + ward filter drive BOTH the map (heatmap) and the list.
  const scopedIssues = useMemo(() => {
    return issues.filter(i =>
      (!zoneFilter || i.zone === zoneFilter) &&
      (!wardFilter || String(i.ward_no) === String(wardFilter))
    );
  }, [issues, zoneFilter, wardFilter]);

  // Table rows: additionally apply the status filter.
  const rows = useMemo(() => {
    if (!statusFilter) return scopedIssues;
    return scopedIssues.filter(i => i.status === statusFilter);
  }, [scopedIssues, statusFilter]);

  // Heatmap center = centroid of the scoped, geolocated issues.
  const center = useMemo(() => {
    const pts = scopedIssues.filter(i => i.latitude && i.longitude);
    if (!pts.length) return null;
    return {
      lat: pts.reduce((s, i) => s + i.latitude, 0) / pts.length,
      lng: pts.reduce((s, i) => s + i.longitude, 0) / pts.length,
    };
  }, [scopedIssues]);

  const counts = useMemo(() => {
    const c = {};
    for (const i of scopedIssues) c[i.status] = (c[i.status] || 0) + 1;
    return c;
  }, [scopedIssues]);

  const total = scopedIssues.length;

  return (
    <div className="flex h-screen flex-col bg-slate-100 text-slate-900">
      {/* Top bar */}
      <header className="flex shrink-0 items-center justify-between border-b border-slate-200 bg-white px-6 py-3">
        <div>
          <h1 className="text-lg font-extrabold">FixMyStreet · Authority Console</h1>
          <p className="text-xs text-slate-500">Density insights & grievance triage</p>
        </div>
        <a href="/" className="flex items-center gap-1 text-sm font-medium text-brand hover:underline">
          <ArrowLeft size={14} /> Citizen App
        </a>
      </header>

      {error && <p className="shrink-0 bg-red-50 px-6 py-2 text-sm text-red-600">{error}</p>}

      {/* ── TOP PANE: dashboard ── */}
      <section className="shrink-0 border-b border-slate-200 bg-white px-6 py-3" style={{ height: "42vh" }}>
        <div className="mb-3 flex items-center gap-2">
          {VIEWS.map(v => {
            const Icon = v.icon;
            return (
              <button
                key={v.key}
                onClick={() => setView(v.key)}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition ${
                  view === v.key ? "bg-slate-800 text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                }`}
              >
                <Icon size={13} /> {v.label}
              </button>
            );
          })}
        </div>

        <div className="h-[calc(42vh-72px)] overflow-y-auto">
          {view === "overview" ? (
            <Overview counts={counts} total={total} issues={scopedIssues} />
          ) : (
            <div className="relative h-full overflow-hidden rounded-xl ring-1 ring-slate-200">
              {center ? (
                <AdminHeatMap
                  issues={scopedIssues}
                  mode={view}
                  center={center}
                  boundaries={boundaries}
                  highlightZone={zoneFilter || null}
                  highlightWard={wardFilter || null}
                />
              ) : (
                <div className="flex h-full items-center justify-center text-sm text-slate-400">No geolocated grievances yet.</div>
              )}
              {/* Heat legend */}
              <div className="absolute bottom-2 right-2 z-[500] flex items-center gap-2 rounded-lg bg-white/90 px-3 py-1.5 text-[10px] font-medium shadow ring-1 ring-slate-200">
                <span className="text-slate-500">{view === "upvotes" ? "Upvote intensity" : "Complaint density"}</span>
                <span className="flex items-center gap-0.5">
                  <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#f59e0b" }} />
                  <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#dc2626" }} />
                  <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#7a1c1c" }} />
                </span>
                <span className="text-slate-400">low → high</span>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* ── BOTTOM PANE: table ── */}
      <section className="flex min-h-0 flex-1 flex-col px-6 py-3">
        {/* Zone / Ward geo filters */}
        <div className="mb-2 flex shrink-0 flex-wrap items-center gap-2">
          <span className="flex items-center gap-1.5 text-xs font-semibold text-slate-500">
            <MapPin size={13} className="text-brand" /> Region
          </span>
          <select
            value={zoneFilter}
            onChange={e => { setZoneFilter(e.target.value); setWardFilter(""); }}
            className="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none focus:border-brand"
          >
            <option value="">All Zones</option>
            {zoneOptions.map(z => (
              <option key={z.zone} value={z.zone}>Zone {z.zone} · {z.name}</option>
            ))}
          </select>
          <select
            value={wardFilter}
            onChange={e => setWardFilter(e.target.value)}
            className="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none focus:border-brand"
          >
            <option value="">All Wards</option>
            {wardOptions.map(w => (
              <option key={w.ward} value={w.ward}>Ward {w.ward}</option>
            ))}
          </select>
          {(zoneFilter || wardFilter) && (
            <button
              onClick={() => { setZoneFilter(""); setWardFilter(""); }}
              className="rounded-full px-2.5 py-1 text-xs font-semibold text-brand ring-1 ring-brand/30 hover:bg-brand-50"
            >
              Clear · {scopedIssues.length} shown
            </button>
          )}
        </div>

        {/* Status filters + sort */}
        <div className="mb-2 flex shrink-0 flex-wrap items-center gap-3">
          <div className="flex items-center gap-1.5">
            <Filter size={13} className="text-slate-400" />
            <div className="flex flex-wrap gap-1.5">
              {FILTERS.map(f => (
                <button
                  key={f.key}
                  onClick={() => setStatusFilter(f.key)}
                  className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
                    statusFilter === f.key ? "bg-brand text-white" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:ring-brand"
                  }`}
                >
                  {f.label}{f.key && counts[f.key] ? ` (${counts[f.key]})` : ""}
                </button>
              ))}
            </div>
          </div>
          <div className="ml-auto flex items-center gap-1.5">
            <ArrowUpDown size={13} className="text-slate-400" />
            {SORTS.map(s => (
              <button
                key={s.key}
                onClick={() => setSortBy(s.key)}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
                  sortBy === s.key ? "bg-slate-800 text-white" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:ring-slate-400"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>

        {/* Table */}
        <div className="min-h-0 flex-1 overflow-y-auto rounded-xl border border-slate-200 bg-white">
          <table className="w-full border-collapse text-sm">
            <thead className="sticky top-0 z-10 bg-slate-50 text-left text-[11px] font-bold uppercase tracking-wide text-slate-500">
              <tr>
                <th className="w-8 px-3 py-2"></th>
                <th className="px-3 py-2">Ticket</th>
                <th className="px-3 py-2">Grievance</th>
                <th className="px-3 py-2 text-center">Zone / Ward</th>
                <th className="px-3 py-2">Department / Route</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2 text-center">Upvotes</th>
                <th className="px-3 py-2">Reporter</th>
                <th className="px-3 py-2">Date</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={9} className="px-3 py-8 text-center text-slate-400">Loading…</td></tr>
              ) : rows.length === 0 ? (
                <tr><td colSpan={9} className="px-3 py-8 text-center text-slate-400">No grievances match this filter.</td></tr>
              ) : (
                rows.map(issue => {
                  const meta = statusMeta(issue.status);
                  const open = expandedId === issue.id;
                  return (
                    <FragmentRow
                      key={issue.id}
                      issue={issue}
                      meta={meta}
                      open={open}
                      busy={busyId === issue.id}
                      onToggle={() => setExpandedId(open ? null : issue.id)}
                      onVerify={() => act(adminVerifyGrievance, issue.id)}
                      onStart={() => act(adminStartIssue, issue.id)}
                      onResolve={() => act(adminCloseIssue, issue.id)}
                      onWhatsapp={() => setWaTarget(issue)}
                    />
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </section>

      {waTarget && <WhatsAppModal issue={waTarget} onClose={() => setWaTarget(null)} />}
    </div>
  );
}

/* ── Overview dashboard (all-in-one) ── */
function Overview({ counts, total, issues }) {
  const cards = [
    { key: "SUBMITTED",            label: "Pending Verification", cls: "bg-violet-50 text-violet-700 ring-violet-200" },
    { key: "ACTIVE",               label: "Assigned",             cls: "bg-brand-50 text-brand-700 ring-brand-200" },
    { key: "IN_PROGRESS",          label: "In Progress",          cls: "bg-orange-50 text-orange-700 ring-orange-200" },
    { key: "PENDING_VERIFICATION", label: "Citizen Verify",       cls: "bg-amber-50 text-amber-700 ring-amber-200" },
    { key: "CLOSED",               label: "Completed",            cls: "bg-green-50 text-green-700 ring-green-200" },
  ];
  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-[1fr_1.2fr]">
      {/* Status breakdown cards */}
      <div className="grid grid-cols-2 content-start gap-2 sm:grid-cols-3">
        <div className="col-span-2 rounded-xl bg-slate-800 p-3 text-white sm:col-span-3">
          <p className="text-[11px] uppercase tracking-wide text-slate-300">Total Grievances</p>
          <p className="text-2xl font-extrabold">{total}</p>
        </div>
        {cards.map(c => (
          <div key={c.key} className={`rounded-xl p-3 ring-1 ${c.cls}`}>
            <p className="text-[11px] font-semibold leading-tight">{c.label}</p>
            <p className="text-xl font-extrabold">{counts[c.key] || 0}</p>
          </div>
        ))}
      </div>

      {/* Checkpoint funnel */}
      <div className="rounded-xl bg-slate-50 p-3 ring-1 ring-slate-200">
        <p className="mb-2 text-[11px] font-bold uppercase tracking-wide text-slate-500">Resolution Funnel</p>
        <div className="space-y-2">
          {FUNNEL.map(step => {
            const n = issues.filter(i => step.match.includes(i.status)).length;
            const pct = total ? Math.round((n / total) * 100) : 0;
            return (
              <div key={step.label}>
                <div className="mb-0.5 flex items-center justify-between text-[11px]">
                  <span className="font-semibold text-slate-600">{step.label}</span>
                  <span className="text-slate-400">{n} · {pct}%</span>
                </div>
                <div className="h-2.5 overflow-hidden rounded-full bg-slate-200">
                  <div className="h-full rounded-full bg-brand" style={{ width: `${pct}%` }} />
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ── One table row + its expandable detail row ── */
function FragmentRow({ issue, meta, open, busy, onToggle, onVerify, onStart, onResolve, onWhatsapp }) {
  const dept = issue.department || "";
  const dmeta = departmentMeta(dept);
  return (
    <>
      <tr
        onClick={onToggle}
        className={`cursor-pointer border-t border-slate-100 hover:bg-slate-50 ${open ? "bg-slate-50" : ""}`}
      >
        <td className="px-3 py-2 text-slate-400">
          {open ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
        </td>
        <td className="px-3 py-2 font-mono text-xs font-semibold text-slate-500">{ticketNumber(issue.id)}</td>
        <td className="px-3 py-2 font-semibold text-slate-800">{issue.title}</td>
        <td className="px-3 py-2 text-center">
          {issue.ward_no != null ? (
            <div className="flex flex-col items-center gap-0.5">
              <span className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-bold text-brand-700 ring-1 ring-brand-200">
                Zone {issue.zone || "—"}
              </span>
              <span className="text-[10px] font-semibold text-slate-500">Ward {issue.ward_no}</span>
            </div>
          ) : <span className="text-slate-400">—</span>}
        </td>
        <td className="px-3 py-2">
          {dept ? (
            <div className="flex items-center gap-1.5">
              <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ring-1 ${dmeta.badge}`}>
                {dmeta.short}
              </span>
              <button
                onClick={(e) => { e.stopPropagation(); onWhatsapp(); }}
                title="Send to department WhatsApp (demo)"
                className="flex h-6 w-6 items-center justify-center rounded-full bg-[#25D366] text-white shadow-sm hover:brightness-95"
              >
                <Send size={11} />
              </button>
            </div>
          ) : <span className="text-slate-400">—</span>}
        </td>
        <td className="px-3 py-2">
          <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${meta.badge}`}>{meta.label}</span>
        </td>
        <td className="px-3 py-2 text-center font-semibold text-orange-600">{issue.upvotes}</td>
        <td className="px-3 py-2 text-slate-600">{issue.phone ? `+91 ${issue.phone}` : "—"}</td>
        <td className="px-3 py-2 whitespace-nowrap text-xs text-slate-500">
          {new Date(issue.created_at).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
        </td>
      </tr>

      {open && (
        <tr className="border-t border-slate-100 bg-slate-50/60">
          <td colSpan={9} className="px-6 py-4">
            <div className="grid grid-cols-1 gap-5 lg:grid-cols-[200px_200px_1fr]">
              {/* Photo */}
              <div>
                <p className="mb-1 text-[10px] font-semibold uppercase text-slate-400">Photo</p>
                {issue.image_url
                  ? <img src={mediaUrl(issue.image_url)} alt="issue" className="h-40 w-full rounded-xl object-cover" />
                  : <div className="flex h-40 w-full items-center justify-center rounded-xl bg-slate-100 text-4xl">🛣️</div>}
              </div>
              {/* Location */}
              <div>
                <p className="mb-1 text-[10px] font-semibold uppercase text-slate-400">Location</p>
                <div className="h-40 w-full overflow-hidden rounded-xl">
                  <MiniMap lat={issue.latitude} lng={issue.longitude} />
                </div>
              </div>
              {/* Details */}
              <div className="space-y-3">
                {/* Routing card */}
                <div className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2">
                  <Building2 size={15} className="text-slate-500" />
                  <div className="min-w-0">
                    <p className="text-[10px] font-semibold uppercase text-slate-400">Routed to (Gemini)</p>
                    <p className="text-sm font-bold text-slate-800">{dept || "Unassigned"}</p>
                  </div>
                  <span className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-semibold text-brand-700 ring-1 ring-brand-200">
                    Zone {issue.zone || "—"}{issue.zone_name ? ` · ${issue.zone_name}` : ""} · Ward {issue.ward_no ?? "—"}
                  </span>
                  <button
                    onClick={(e) => { e.stopPropagation(); onWhatsapp(); }}
                    className="ml-auto flex items-center gap-1.5 rounded-lg bg-[#25D366] px-3 py-1.5 text-xs font-bold text-white shadow-sm hover:brightness-95"
                  >
                    <Send size={12} /> WhatsApp
                  </button>
                </div>

                {issue.phone && (
                  <div className="flex items-center gap-2 rounded-lg border border-brand-100 bg-brand-50 px-3 py-2">
                    <Phone size={14} className="text-brand" />
                    <span className="text-sm font-bold text-slate-800">+91 {issue.phone}</span>
                  </div>
                )}
                <div>
                  <p className="mb-1 text-[10px] font-semibold uppercase text-slate-400">Transcript</p>
                  <p className="rounded-lg bg-white p-2.5 text-sm italic text-slate-700 ring-1 ring-slate-200">
                    "{issue.transcript || "No transcript"}"
                  </p>
                </div>
                {issue.summary_highlights?.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {issue.summary_highlights.map((h, i) => (
                      <span key={i} className="rounded-full bg-brand-50 px-2.5 py-0.5 text-xs font-medium text-brand ring-1 ring-brand-100">{h}</span>
                    ))}
                  </div>
                )}

                {/* Actions */}
                <div className="flex flex-wrap items-center gap-2 pt-1">
                  {issue.status === "SUBMITTED" && (
                    <button onClick={(e) => { e.stopPropagation(); onVerify(); }} disabled={busy}
                      className="flex items-center gap-1.5 rounded-lg bg-violet-600 px-4 py-2 text-sm font-bold text-white disabled:opacity-60">
                      <ShieldCheck size={14} /> Verify Grievance
                    </button>
                  )}
                  {issue.status === "ACTIVE" && (
                    <button onClick={(e) => { e.stopPropagation(); onStart(); }} disabled={busy}
                      className="flex items-center gap-1.5 rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold disabled:opacity-60">
                      <PlayCircle size={14} /> Accept & Start Work
                    </button>
                  )}
                  {(issue.status === "ACTIVE" || issue.status === "IN_PROGRESS") && (
                    <button onClick={(e) => { e.stopPropagation(); onResolve(); }} disabled={busy}
                      className="flex items-center gap-1.5 rounded-lg bg-green-600 px-4 py-2 text-sm font-bold text-white disabled:opacity-60">
                      <CheckCircle2 size={14} /> Mark as Resolved
                    </button>
                  )}
                  {issue.status === "PENDING_VERIFICATION" && (
                    <p className="flex items-center gap-1.5 text-sm font-medium text-amber-700">
                      <Clock size={14} /> Awaiting citizen verification…
                    </p>
                  )}
                  {issue.status === "CLOSED" && (
                    <p className="flex items-center gap-1.5 text-sm font-medium text-green-700">
                      <CheckCircle2 size={14} /> Resolved & verified.
                    </p>
                  )}
                </div>
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
