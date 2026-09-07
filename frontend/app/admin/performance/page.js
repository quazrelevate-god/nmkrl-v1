"use client";

/**
 * Performance — glassmorphism analytics workspace.
 *   • Density map (heatmap) with ward / zone / constituency filters.
 *   • Community Pulse — polls, threads and replies from the citizen feed.
 *   • Grievance KPIs + charts computed from real data.
 *
 * Charts live in components/admin/charts.js. Each form is chosen for the job
 * its data does rather than reusing one bar component six times, and every
 * multi-hue set was run through the CVD validator.
 */

import { useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  LayoutDashboard, Flame, ThumbsUp, Ticket, CheckCircle2, TimerOff, Clock, Gauge,
  MapPin, TrendingUp, Sparkles, Activity, Layers, Building2,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import { departmentMeta } from "@/lib/departments";
import { derivePriority, slaBreached, daysOpen } from "@/lib/adminModel";
import { CONSTITUENCIES, issueInConstituency, shortAC, constituenciesForWard } from "@/lib/constituencies";
import CommunityPulse from "@/components/admin/CommunityPulse";
import {
  VIZ, ChartCard, TrendChart, Funnel, Donut, StackedShare, RankedBars,
  RankedTable, StatTile,
} from "@/components/admin/charts";

const AdminHeatMap = dynamic(() => import("@/components/AdminHeatMap"), {
  ssr: false,
  loading: () => <div className="flex h-full items-center justify-center text-sm text-slate-400">Loading map…</div>,
});

const DEFAULT_AC = "20 - Anna Nagar";

export default function PerformancePage() {
  const { issues, boundaries, loading } = useAdminData();
  const [mode, setMode] = useState("complaints");
  const [zone, setZone] = useState("");
  const [ward, setWard] = useState("");
  const [ac, setAc] = useState("");
  const [kpiFilter, setKpiFilter] = useState(null); // click a KPI card to plot it on the map

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
    (!zone || String(i.zone) === zone) && (!ward || String(i.ward_no) === ward) &&
    issueInConstituency(i, ac)), [issues, zone, ward, ac]);

  const center = useMemo(() => {
    const pts = scoped.filter((i) => i.latitude && i.longitude);
    if (!pts.length) return null;
    return { lat: pts.reduce((s, i) => s + i.latitude, 0) / pts.length, lng: pts.reduce((s, i) => s + i.longitude, 0) / pts.length };
  }, [scoped]);

  const kpi = useMemo(() => computeKpis(scoped), [scoped]);

  // KPI cards double as map filters: clicking one plots its grievances at their
  // real coordinates in the same colour as the card's number.
  const kpiCards = useMemo(() => [
    { key: "total", label: "Total", icon: Ticket, tone: "text-slate-800", color: "#475569", value: kpi.total, match: () => true },
    { key: "pending", label: "Pending Review", icon: Clock, tone: "text-violet-600", color: "#7c3aed", value: kpi.pending, match: (i) => i.status === "SUBMITTED" },
    { key: "open", label: "Open", icon: Ticket, tone: "text-brand", color: "#7a1c1c", value: kpi.open, match: (i) => ["ACTIVE", "FORWARDED"].includes(i.status) },
    { key: "inProgress", label: "In Progress", icon: Gauge, tone: "text-amber-600", color: "#d97706", value: kpi.inProgress, match: (i) => i.status === "IN_PROGRESS" },
    { key: "resolved", label: "Resolved", icon: CheckCircle2, tone: "text-emerald-600", color: "#059669", value: kpi.resolved, match: (i) => ["PENDING_VERIFICATION", "CLOSED"].includes(i.status) },
    { key: "breached", label: "SLA Breached", icon: TimerOff, tone: "text-red-500", color: "#ef4444", value: kpi.breached, match: slaBreached },
    { key: "rate", label: "Resolution Rate", icon: Gauge, tone: "text-brand", value: `${kpi.resolutionRate}%`, filterable: false },
  ], [kpi]);

  const activeKpi = kpiCards.find((c) => c.key === kpiFilter && c.match);
  const overlay = activeKpi
    ? {
        issues: scoped.filter((i) => activeKpi.match(i) && i.latitude != null && i.longitude != null),
        color: activeKpi.color,
        label: activeKpi.label,
      }
    : null;

  return (
    <>
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand"><LayoutDashboard size={20} /></div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Performance</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Density insights & grievance analytics</p>
          </div>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5 space-y-5">
        {/* Filter bar */}
        <div className="glass-panel flex flex-wrap items-center gap-2 rounded-2xl px-4 py-3">
          <span className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-slate-400"><MapPin size={13} className="text-brand" /> Density map</span>
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
          <div className="ml-auto flex items-center gap-1 rounded-lg bg-white/50 p-1 ring-1 ring-white/60">
            <ModeBtn active={mode === "complaints"} onClick={() => setMode("complaints")} icon={Flame}>Complaint density</ModeBtn>
            <ModeBtn active={mode === "upvotes"} onClick={() => setMode("upvotes")} icon={ThumbsUp}>Upvote hotspots</ModeBtn>
          </div>
        </div>

        {/* Density map — full content width */}
        <div className="glass-panel relative h-[46vh] overflow-hidden rounded-2xl">
            {center ? (
              <AdminHeatMap issues={scoped} mode={mode} center={center} boundaries={boundaries}
                highlightZone={zone || null} highlightWard={ward || null} overlay={overlay} />
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-slate-400">
                {loading ? "Loading map…" : "No geolocated grievances for this filter."}
              </div>
            )}
            <div className="absolute bottom-3 right-3 z-[500] flex items-center gap-2 rounded-lg bg-white/85 px-3 py-1.5 text-[10px] font-medium shadow ring-1 ring-white/60 backdrop-blur">
              {overlay ? (
                <>
                  <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: overlay.color }} />
                  <span className="font-bold" style={{ color: overlay.color }}>{overlay.label}</span>
                  <span className="text-slate-400">· {overlay.issues.length} on map</span>
                  <button onClick={() => setKpiFilter(null)} className="ml-1 text-slate-400 hover:text-slate-700"><X size={12} /></button>
                </>
              ) : (
                <>
                  <span className="text-slate-500">{mode === "upvotes" ? "Upvote intensity" : "Complaint density"}</span>
                  <span className="flex items-center gap-0.5">
                    {["#16a34a", "#f59e0b", "#dc2626"].map((c) => <span key={c} className="inline-block h-2 w-2 rounded-full" style={{ background: c }} />)}
                  </span>
                  <span className="text-slate-400">low → high</span>
                </>
              )}
            </div>
        </div>

        {/* Community pulse — polls, threads and replies from the citizen feed */}
        <CommunityPulse ac={ac} />

        {/* Grievance KPIs */}
        <SectionTitle icon={Ticket}>
          Grievance overview{ac ? ` · ${shortAC(ac)}` : ""}
          <span className="ml-1 text-[11px] font-medium normal-case text-slate-400">— click a card to plot it on the map</span>
        </SectionTitle>
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4 xl:grid-cols-7">
          {kpiCards.map((c) => (
            <Kpi
              key={c.key}
              label={c.label}
              value={c.value}
              icon={c.icon}
              tone={c.tone}
              color={c.color}
              active={kpiFilter === c.key}
              onClick={c.filterable === false ? undefined : () => setKpiFilter(kpiFilter === c.key ? null : c.key)}
            />
          ))}
        </div>

        {/* ── Charts ──────────────────────────────────────────────────────
            Six forms, one per job: trend, funnel, part-to-whole, ordered
            share, magnitude, and a table where colour would stop helping. */}
        <SectionTitle icon={Activity}>Analytics</SectionTitle>

        <ChartCard
          title="Intake vs resolution"
          subtitle="Grievances reported and closed per day, last 30 days"
          right={
            <span className="flex items-center gap-3 text-[11px] text-slate-500">
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full" style={{ background: VIZ.series1 }} /> Reported
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full" style={{ background: VIZ.series2 }} /> Resolved
              </span>
            </span>
          }
        >
          <TrendChart series={kpi.trend} />
        </ChartCard>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <ChartCard title="Lifecycle funnel" subtitle="How far grievances get, and where they stall">
            <Funnel stages={kpi.funnel} />
          </ChartCard>

          <ChartCard title="Priority mix" subtitle="Derived from age, supports and SLA">
            <Donut segments={kpi.priorityDonut} total={kpi.total} label="grievances" />
          </ChartCard>

          <ChartCard title="Ageing of open grievances" subtitle="Days since reported — darker is older">
            <StackedShare
              segments={kpi.ageing}
              caption={`${kpi.avgOpen} days average, oldest open ${kpi.oldest} days.`}
            />
          </ChartCard>

          <ChartCard title="Department load" subtitle="Top five by routed volume">
            <RankedBars data={kpi.deptBars} empty="No routed grievances yet" />
          </ChartCard>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <ChartCard title="Hotspot zones" subtitle="Where the volume is concentrated">
            <RankedTable rows={kpi.zoneBars} headers={["Zone", "Count", "Share"]} empty="No zoned grievances" />
          </ChartCard>
          <ChartCard title="Hotspot constituencies" subtitle="Grievances by assembly constituency">
            <RankedTable rows={kpi.acBars} headers={["Constituency", "Count", "Share"]} empty="No mapped constituencies" />
          </ChartCard>
        </div>

        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile label="Avg days open" value={kpi.avgOpen} suffix="d" icon={Clock} />
          <StatTile label="Oldest open" value={kpi.oldest} suffix="d" icon={TimerOff} tone="text-rose-600" />
          <StatTile label="Avg supports" value={kpi.avgUpvotes} icon={ThumbsUp} />
          <StatTile label="On-track SLA" value={kpi.onTrackRate} suffix="%" icon={Gauge} tone="text-emerald-600" />
        </div>

      </div>
    </>
  );
}

const selectCls = "rounded-lg border border-white/60 bg-white/60 px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none backdrop-blur focus:border-brand";
const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

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

  // Funnel: each stage is everything that reached AT LEAST that far, so the
  // widths read as drop-off rather than as four unrelated buckets.
  const reachedCoordinator = total - pending;
  const reachedDept = by("FORWARDED") + by("IN_PROGRESS") + resolved;
  const funnel = [
    { label: "Reported", value: total },
    { label: "Picked up by a coordinator", value: reachedCoordinator },
    { label: "Routed to a department", value: reachedDept },
    { label: "Resolved", value: resolved },
  ];

  // Ageing of what is still open — an ordered scale, so a sequential ramp.
  const buckets = [0, 0, 0, 0];
  for (const i of openIssues) {
    const d = daysOpen(i);
    buckets[d <= 3 ? 0 : d <= 7 ? 1 : d <= 14 ? 2 : 3]++;
  }
  const ageing = [
    { label: "0–3 days", value: buckets[0] },
    { label: "4–7 days", value: buckets[1] },
    { label: "8–14 days", value: buckets[2] },
    { label: "15+ days", value: buckets[3] },
  ];

  // 30-day intake vs resolution. Both series are grievances per day — one
  // unit, one axis; never a second scale.
  const DAYS = 30;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const dayKey = (d) => new Date(d).toISOString().slice(0, 10);
  const reportedBy = {}, resolvedBy = {};
  for (const i of issues) {
    if (i.created_at) reportedBy[dayKey(i.created_at)] = (reportedBy[dayKey(i.created_at)] || 0) + 1;
    const done = i.resolved_at || i.closed_at;
    if (done) resolvedBy[dayKey(done)] = (resolvedBy[dayKey(done)] || 0) + 1;
  }
  const axis = [];
  for (let k = DAYS - 1; k >= 0; k--) {
    const d = new Date(today); d.setDate(d.getDate() - k);
    axis.push({ key: dayKey(d), label: d.toLocaleDateString("en-IN", { day: "numeric", month: "short" }) });
  }
  const trend = [
    { label: "Reported", color: "#2a78d6", fill: true, points: axis.map((a) => ({ label: a.label, value: reportedBy[a.key] || 0 })) },
    { label: "Resolved", color: "#1baf7a", points: axis.map((a) => ({ label: a.label, value: resolvedBy[a.key] || 0 })) },
  ];
  const prio = { High: 0, Medium: 0, Low: 0 };
  for (const i of issues) prio[derivePriority(i)]++;
  // Validated trio (red / yellow / aqua): passes CVD separation and the
  // normal-vision floor. Every slice is labelled beside the ring, which is
  // what the contrast warning against white obliges.
  const priorityDonut = [
    { label: "High", value: prio.High, color: "#e34948" },
    { label: "Medium", value: prio.Medium, color: "#eda100" },
    { label: "Low", value: prio.Low, color: "#1baf7a" },
  ];
  const deptCount = {};
  for (const i of issues) if (i.department) { const k = departmentMeta(i.department).short; deptCount[k] = (deptCount[k] || 0) + 1; }
  const deptBars = topBars(deptCount);
  const zoneCount = {};
  for (const i of issues) if (i.zone) { const k = `Zone ${i.zone}`; zoneCount[k] = (zoneCount[k] || 0) + 1; }
  const zoneBars = topBars(zoneCount, 6);
  const acCount = {};
  for (const i of issues) for (const a of constituenciesForWard(i.ward_no)) { const k = shortAC(a); acCount[k] = (acCount[k] || 0) + 1; }
  const acBars = topBars(acCount, 6);

  return { total, pending, open, inProgress, resolved, breached, resolutionRate,
    avgOpen, oldest, avgUpvotes, onTrackRate, funnel, ageing, trend,
    priorityDonut, deptBars, zoneBars, acBars };
}
function topBars(countMap, n = 5) {
  return Object.entries(countMap).map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value).slice(0, n);
}

/* ── UI atoms ── */
function SectionTitle({ icon: Icon, children }) {
  return <p className="flex items-center gap-2 pt-1 text-sm font-extrabold text-slate-700"><Icon size={16} className="text-brand" /> {children}</p>;
}
function ModeBtn({ active, onClick, icon: Icon, children }) {
  return (
    <button onClick={onClick} style={{ transition: "all .3s cubic-bezier(.22,1,.36,1)" }}
      className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-bold ${active ? "bg-gradient-to-r from-brand to-brand-dark text-white" : "text-slate-500"}`}>
      <Icon size={13} /> {children}
    </button>
  );
}
function Kpi({ label, value, icon: Icon, tone, color, active, onClick }) {
  const clickable = !!onClick;
  return (
    <div
      onClick={onClick}
      role={clickable ? "button" : undefined}
      className={`glass-panel rounded-2xl p-4 ${clickable ? "glass-hover cursor-pointer" : ""}`}
      style={active ? { outline: `2px solid ${color}`, outlineOffset: "-2px", background: "rgba(255,255,255,0.62)" } : undefined}
    >
      <div className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-400"><Icon size={12} /> {label}</div>
      <p className={`text-2xl font-extrabold ${tone}`}>{value}</p>
    </div>
  );
}
