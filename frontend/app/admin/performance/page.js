"use client";

/**
 * Performance — analytics workspace.
 *   • TOP  : live density map (heatmap) with ward / zone / constituency filters
 *            and complaint-vs-upvote weighting.
 *   • BELOW: KPI cards + dependency-free charts computed from the real issue
 *            data (status funnel, department load, priority split, geo hotspots,
 *            resolution rate, SLA health).
 */

import { useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  LayoutDashboard, Flame, ThumbsUp, Ticket, CheckCircle2, TimerOff,
  Clock, Gauge, MapPin,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import { departmentMeta } from "@/lib/departments";
import { derivePriority, PRIORITY_META, slaBreached, daysOpen } from "@/lib/adminModel";
import { CONSTITUENCIES, issueInConstituency, shortAC, constituenciesForWard } from "@/lib/constituencies";

const AdminHeatMap = dynamic(() => import("@/components/AdminHeatMap"), {
  ssr: false,
  loading: () => <div className="flex h-full items-center justify-center text-sm text-slate-400">Loading map…</div>,
});

export default function PerformancePage() {
  const { issues, boundaries, loading } = useAdminData();
  const [mode, setMode] = useState("complaints");
  const [zone, setZone] = useState("");
  const [ward, setWard] = useState("");
  const [ac, setAc] = useState("");

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

  const scoped = useMemo(() => issues.filter((i) =>
    (!zone || String(i.zone) === zone) &&
    (!ward || String(i.ward_no) === ward) &&
    issueInConstituency(i, ac)), [issues, zone, ward, ac]);

  const center = useMemo(() => {
    const pts = scoped.filter((i) => i.latitude && i.longitude);
    if (!pts.length) return null;
    return { lat: pts.reduce((s, i) => s + i.latitude, 0) / pts.length, lng: pts.reduce((s, i) => s + i.longitude, 0) / pts.length };
  }, [scoped]);

  const kpi = useMemo(() => computeKpis(scoped), [scoped]);

  return (
    <>
      <header className="flex items-center justify-between border-b border-slate-200 bg-white px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-100 text-blue-600"><LayoutDashboard size={20} /></div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Performance</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Density insights & grievance analytics</p>
          </div>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5 space-y-5">
        {/* Filter bar */}
        <div className="flex flex-wrap items-center gap-2 rounded-2xl border border-slate-200 bg-white px-4 py-3 shadow-sm">
          <span className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-slate-400"><MapPin size={13} className="text-blue-500" /> Density map</span>
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
          <div className="ml-auto flex items-center gap-1 rounded-lg bg-slate-100 p-1">
            <ModeBtn active={mode === "complaints"} onClick={() => setMode("complaints")} icon={Flame}>Complaint density</ModeBtn>
            <ModeBtn active={mode === "upvotes"} onClick={() => setMode("upvotes")} icon={ThumbsUp}>Upvote hotspots</ModeBtn>
          </div>
        </div>

        {/* Map (top half) */}
        <div className="relative h-[46vh] overflow-hidden rounded-2xl border border-slate-200 shadow-sm">
          {center ? (
            <AdminHeatMap issues={scoped} mode={mode} center={center} boundaries={boundaries}
              highlightZone={zone || null} highlightWard={ward || null} />
          ) : (
            <div className="flex h-full items-center justify-center text-sm text-slate-400">
              {loading ? "Loading map…" : "No geolocated grievances for this filter."}
            </div>
          )}
          <div className="absolute bottom-3 right-3 z-[500] flex items-center gap-2 rounded-lg bg-white/90 px-3 py-1.5 text-[10px] font-medium shadow ring-1 ring-slate-200">
            <span className="text-slate-500">{mode === "upvotes" ? "Upvote intensity" : "Complaint density"}</span>
            <span className="flex items-center gap-0.5">
              {["#f59e0b", "#dc2626", "#7a1c1c"].map((c) => <span key={c} className="inline-block h-2 w-2 rounded-full" style={{ background: c }} />)}
            </span>
            <span className="text-slate-400">low → high</span>
          </div>
        </div>

        {/* KPI cards */}
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4 xl:grid-cols-7">
          <Kpi label="Total" value={kpi.total} icon={Ticket} tone="text-slate-800" />
          <Kpi label="Pending Review" value={kpi.pending} icon={Clock} tone="text-violet-600" />
          <Kpi label="Open" value={kpi.open} icon={Ticket} tone="text-blue-600" />
          <Kpi label="In Progress" value={kpi.inProgress} icon={Gauge} tone="text-amber-600" />
          <Kpi label="Resolved" value={kpi.resolved} icon={CheckCircle2} tone="text-emerald-600" />
          <Kpi label="SLA Breached" value={kpi.breached} icon={TimerOff} tone="text-red-500" />
          <Kpi label="Resolution Rate" value={`${kpi.resolutionRate}%`} icon={Gauge} tone="text-blue-600" />
        </div>

        {/* Charts */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card title="Status funnel">
            <Bars data={kpi.statusBars} />
          </Card>
          <Card title="Priority split">
            <div className="flex items-center gap-5">
              <Donut segments={kpi.priorityDonut} total={kpi.total} />
              <div className="space-y-2">
                {kpi.priorityDonut.map((s) => (
                  <div key={s.label} className="flex items-center gap-2 text-sm">
                    <span className="h-3 w-3 rounded-sm" style={{ background: s.color }} />
                    <span className="font-semibold text-slate-700">{s.label}</span>
                    <span className="text-slate-400">{s.value}</span>
                  </div>
                ))}
              </div>
            </div>
          </Card>
          <Card title="Department load">
            <Bars data={kpi.deptBars} empty="No routed grievances yet" />
          </Card>
          <Card title="Average resolution & ageing">
            <div className="grid grid-cols-2 gap-3">
              <Stat label="Avg days open" value={kpi.avgOpen} suffix="d" />
              <Stat label="Oldest open" value={kpi.oldest} suffix="d" />
              <Stat label="Avg upvotes" value={kpi.avgUpvotes} />
              <Stat label="On-track SLA" value={`${kpi.onTrackRate}%`} />
            </div>
          </Card>
          <Card title="Hotspot zones">
            <Bars data={kpi.zoneBars} empty="No zoned grievances" />
          </Card>
          <Card title="Hotspot constituencies">
            <Bars data={kpi.acBars} empty="No mapped constituencies" />
          </Card>
        </div>
      </div>
    </>
  );
}

const selectCls = "rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none focus:border-blue-500";

/* ── analytics ── */
function computeKpis(issues) {
  const total = issues.length;
  const by = (s) => issues.filter((i) => i.status === s).length;
  const pending = by("SUBMITTED");
  const open = by("ACTIVE") + by("FORWARDED");
  const inProgress = by("IN_PROGRESS");
  const resolved = by("PENDING_VERIFICATION") + by("CLOSED");
  const closed = by("CLOSED");
  const breached = issues.filter(slaBreached).length;
  const resolutionRate = total ? Math.round((closed / total) * 100) : 0;

  const openIssues = issues.filter((i) => !["CLOSED", "PENDING_VERIFICATION"].includes(i.status));
  const ages = openIssues.map(daysOpen);
  const avgOpen = ages.length ? Math.round(ages.reduce((a, b) => a + b, 0) / ages.length) : 0;
  const oldest = ages.length ? Math.max(...ages) : 0;
  const avgUpvotes = total ? Math.round(issues.reduce((s, i) => s + (i.upvotes || 0), 0) / total * 10) / 10 : 0;
  const onTrackRate = openIssues.length ? Math.round((1 - breached / Math.max(1, openIssues.length)) * 100) : 100;

  const statusBars = [
    { label: "Pending", value: pending, color: "#7c3aed" },
    { label: "Open", value: open, color: "#2563eb" },
    { label: "In Progress", value: inProgress, color: "#f59e0b" },
    { label: "Resolved", value: resolved, color: "#059669" },
  ];

  const prio = { High: 0, Medium: 0, Low: 0 };
  for (const i of issues) prio[derivePriority(i)]++;
  const priorityDonut = [
    { label: "High", value: prio.High, color: PRIORITY_META.High.dot },
    { label: "Medium", value: prio.Medium, color: PRIORITY_META.Medium.dot },
    { label: "Low", value: prio.Low, color: PRIORITY_META.Low.dot },
  ];

  const deptCount = {};
  for (const i of issues) if (i.department) deptCount[departmentMeta(i.department).short] = (deptCount[departmentMeta(i.department).short] || 0) + 1;
  const deptBars = topBars(deptCount, "#0ea5e9");

  const zoneCount = {};
  for (const i of issues) if (i.zone) { const k = `Zone ${i.zone}`; zoneCount[k] = (zoneCount[k] || 0) + 1; }
  const zoneBars = topBars(zoneCount, "#7a1c1c");

  const acCount = {};
  for (const i of issues) for (const a of constituenciesForWard(i.ward_no)) { const k = shortAC(a); acCount[k] = (acCount[k] || 0) + 1; }
  const acBars = topBars(acCount, "#6366f1");

  return { total, pending, open, inProgress, resolved, breached, resolutionRate,
    avgOpen, oldest, avgUpvotes, onTrackRate, statusBars, priorityDonut, deptBars, zoneBars, acBars };
}

function topBars(countMap, color, n = 5) {
  return Object.entries(countMap).map(([label, value]) => ({ label, value, color }))
    .sort((a, b) => b.value - a.value).slice(0, n);
}

/* ── UI atoms ── */
function ModeBtn({ active, onClick, icon: Icon, children }) {
  return (
    <button onClick={onClick} className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-bold transition ${active ? "bg-white text-slate-800 shadow-sm" : "text-slate-500"}`}>
      <Icon size={13} /> {children}
    </button>
  );
}
function Kpi({ label, value, icon: Icon, tone }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-400"><Icon size={12} /> {label}</div>
      <p className={`text-2xl font-extrabold ${tone}`}>{value}</p>
    </div>
  );
}
function Card({ title, children }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <p className="mb-3 text-sm font-bold text-slate-700">{title}</p>
      {children}
    </div>
  );
}
function Bars({ data, empty = "No data" }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  if (!data.length || max === 0) return <p className="py-6 text-center text-xs text-slate-400">{empty}</p>;
  return (
    <div className="space-y-2.5">
      {data.map((d) => (
        <div key={d.label}>
          <div className="mb-0.5 flex items-center justify-between text-[12px]">
            <span className="font-semibold text-slate-600">{d.label}</span>
            <span className="text-slate-400">{d.value}</span>
          </div>
          <div className="h-2.5 overflow-hidden rounded-full bg-slate-100">
            <div className="h-full rounded-full" style={{ width: `${(d.value / max) * 100}%`, background: d.color }} />
          </div>
        </div>
      ))}
    </div>
  );
}
function Donut({ segments, total }) {
  const size = 108, stroke = 18, r = (size - stroke) / 2, circ = 2 * Math.PI * r;
  let offset = 0;
  const sum = segments.reduce((s, x) => s + x.value, 0) || 1;
  return (
    <svg width={size} height={size} className="shrink-0 -rotate-90">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#f1f5f9" strokeWidth={stroke} />
      {segments.map((s) => {
        const len = (s.value / sum) * circ;
        const el = <circle key={s.label} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={s.color}
          strokeWidth={stroke} strokeDasharray={`${len} ${circ - len}`} strokeDashoffset={-offset} />;
        offset += len;
        return el;
      })}
      <text x="50%" y="50%" className="rotate-90" transform={`rotate(90 ${size / 2} ${size / 2})`}
        textAnchor="middle" dominantBaseline="central" fontSize="20" fontWeight="800" fill="#0f172a">{total}</text>
    </svg>
  );
}
function Stat({ label, value, suffix = "" }) {
  return (
    <div className="rounded-xl bg-slate-50 p-3">
      <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
      <p className="text-xl font-extrabold text-slate-800">{value}{suffix}</p>
    </div>
  );
}
