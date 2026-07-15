"use client";

/**
 * Performance — glassmorphism analytics workspace.
 *   • Density map (heatmap) with ward / zone / constituency filters.
 *   • MLA social-media trending mentions (mock) tied to the selected AC.
 *   • Grievance KPIs + charts computed from real data.
 *   • Community Pulse — engagement KPIs from the citizen app's feed.
 *   • Content Moderation — community posts flagged as abusive / violating.
 */

import { useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  LayoutDashboard, Flame, ThumbsUp, Ticket, CheckCircle2, TimerOff, Clock, Gauge,
  MapPin, Megaphone, TrendingUp, Users, MessageCircle,
  Share2, BarChart3, Sparkles, ShieldAlert, ShieldCheck, Trash2, Heart, X,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import { departmentMeta } from "@/lib/departments";
import { derivePriority, PRIORITY_META, slaBreached, daysOpen } from "@/lib/adminModel";
import { CONSTITUENCIES, issueInConstituency, shortAC, constituenciesForWard } from "@/lib/constituencies";
import { communityKpis, FLAGGED_CONTENT } from "@/lib/communityInsights";
import TodaysPulse from "@/components/community/TodaysPulse";
import NammKuralPulse from "@/components/admin/NammKuralPulse";

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
  const [flagged, setFlagged] = useState(FLAGGED_CONTENT);
  const [resolvedMod, setResolvedMod] = useState({});
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
  const community = useMemo(() => communityKpis(), []);

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

  function actMod(id, kind) {
    setResolvedMod((m) => ({ ...m, [id]: kind }));
    setTimeout(() => setFlagged((f) => f.filter((x) => x.id !== id)), 260);
  }

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

        {/* Map + MLA social mentions */}
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-[1.6fr_1fr]">
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

          {/* Social Mentions column — Today's Pulse card (from /coordinator),
              bounded to the map's height so the layout mirrors the previous
              two-column shape. Internal scroll for the news carousel. */}
          <div className="h-[46vh] min-h-0 overflow-hidden">
            <div className="no-scrollbar h-full overflow-y-auto rounded-3xl">
              <TodaysPulse constituency={ac || DEFAULT_AC} variant="admin" />
            </div>
          </div>
        </div>

        {/* நம் குரல் pulse — media + social listening briefing for the MLA */}
        <NammKuralPulse ac={ac || DEFAULT_AC} isDefault={!ac} />

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

        {/* Charts */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card title="Status funnel"><Bars data={kpi.statusBars} /></Card>
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
          <Card title="Department load"><Bars data={kpi.deptBars} empty="No routed grievances yet" /></Card>
          <Card title="Average resolution & ageing">
            <div className="grid grid-cols-2 gap-3">
              <Stat label="Avg days open" value={kpi.avgOpen} suffix="d" />
              <Stat label="Oldest open" value={kpi.oldest} suffix="d" />
              <Stat label="Avg upvotes" value={kpi.avgUpvotes} />
              <Stat label="On-track SLA" value={`${kpi.onTrackRate}%`} />
            </div>
          </Card>
          <Card title="Hotspot zones"><Bars data={kpi.zoneBars} empty="No zoned grievances" /></Card>
          <Card title="Hotspot constituencies"><Bars data={kpi.acBars} empty="No mapped constituencies" /></Card>
        </div>

        {/* Community Pulse */}
        <SectionTitle icon={Sparkles}>Community pulse · citizen app engagement</SectionTitle>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <Kpi label="Posts" value={community.posts} icon={Megaphone} tone="text-slate-800" />
          <Kpi label="Engaged Voices" value={community.voices} icon={Users} tone="text-brand" />
          <Kpi label="Likes" value={fmt(community.likes)} icon={Heart} tone="text-rose-500" />
          <Kpi label="Comments" value={fmt(community.comments)} icon={MessageCircle} tone="text-amber-600" />
          <Kpi label="Shares" value={fmt(community.shares)} icon={Share2} tone="text-emerald-600" />
          <Kpi label="Poll Votes" value={fmt(community.pollVotes)} icon={BarChart3} tone="text-violet-600" />
        </div>
        {community.top && (
          <div className="glass-panel flex flex-wrap items-center gap-2 rounded-2xl px-4 py-3 text-sm">
            <span className="rounded-md bg-gradient-to-r from-amber-400 to-amber-500 px-2 py-0.5 text-[11px] font-bold text-brand-dark">TOP POST</span>
            <span className="font-semibold text-slate-800">{community.top.title}</span>
            <span className="text-slate-400">by {community.top.author}</span>
            <span className="ml-auto flex items-center gap-1 font-bold text-brand"><TrendingUp size={14} /> {fmt(community.top.eng)} engagements</span>
          </div>
        )}

        {/* Content Moderation */}
        <SectionTitle icon={ShieldAlert}>
          Content moderation · flagged community content
          {flagged.length > 0 && <span className="rounded-full bg-red-500 px-2 py-0.5 text-[11px] font-bold text-white">{flagged.length}</span>}
        </SectionTitle>
        <div className="glass-panel-strong overflow-hidden rounded-2xl">
          {flagged.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-12 text-center text-slate-400">
              <ShieldCheck size={36} className="text-emerald-400" />
              <p className="font-semibold">Queue clear — no flagged community content pending review.</p>
            </div>
          ) : flagged.map((f) => (
            <ModerationRow key={f.id} item={f} resolved={resolvedMod[f.id]} onAct={actMod} />
          ))}
        </div>
      </div>
    </>
  );
}

const selectCls = "rounded-lg border border-white/60 bg-white/60 px-2.5 py-1.5 text-xs font-semibold text-slate-700 outline-none backdrop-blur focus:border-brand";
const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

/* ── Moderation row ── */
function ModerationRow({ item, resolved, onAct }) {
  const high = item.severity === "High";
  return (
    <div className={`flex flex-wrap items-start gap-3 border-t border-white/40 px-5 py-4 first:border-t-0 ${resolved ? "opacity-40" : ""}`}
      style={{ transition: "opacity .25s ease" }}>
      <span className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${high ? "bg-red-100 text-red-600" : "bg-amber-100 text-amber-700"}`}>
        <ShieldAlert size={16} />
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <span className={`rounded-md px-2 py-0.5 text-[10px] font-bold ${high ? "bg-red-500 text-white" : "bg-amber-400 text-amber-950"}`}>{item.severity}</span>
          <span className="text-sm font-bold text-slate-800">{item.reason}</span>
          <span className="text-[11px] text-slate-400">· model score {item.score}</span>
        </div>
        <p className="mt-1 rounded-lg bg-red-50/60 px-3 py-2 text-sm italic text-slate-700 ring-1 ring-red-100">“{item.text}”</p>
        <p className="mt-1 text-[11px] text-slate-400">@{item.author} · {item.area} · {item.context}</p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {resolved ? (
          <span className="text-xs font-bold text-slate-500">{resolved === "remove" ? "Removed" : "Kept"}</span>
        ) : (
          <>
            <button onClick={() => onAct(item.id, "keep")} title="Verify as safe / keep"
              style={{ transition: "all .25s ease" }}
              className="flex items-center gap-1 rounded-lg border border-slate-300 bg-white/70 px-3 py-1.5 text-xs font-bold text-slate-600 hover:-translate-y-px hover:bg-white">
              <ShieldCheck size={13} /> Keep
            </button>
            <button onClick={() => onAct(item.id, "remove")} title="Remove violating content"
              style={{ transition: "all .25s ease" }}
              className="flex items-center gap-1 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-bold text-white hover:-translate-y-px hover:bg-red-700">
              <Trash2 size={13} /> Remove
            </button>
          </>
        )}
      </div>
    </div>
  );
}

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
    { label: "Open", value: open, color: "#7a1c1c" },
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
  for (const i of issues) if (i.department) { const k = departmentMeta(i.department).short; deptCount[k] = (deptCount[k] || 0) + 1; }
  const deptBars = topBars(deptCount, "#c99a2e");
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
function Card({ title, children }) {
  return (
    <div className="glass-panel rounded-2xl p-5">
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
          <div className="h-2.5 overflow-hidden rounded-full bg-slate-200/70">
            <div className="h-full rounded-full" style={{ width: `${(d.value / max) * 100}%`, background: d.color, transition: "width .5s cubic-bezier(.22,1,.36,1)" }} />
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
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#e2e8f0" strokeWidth={stroke} />
      {segments.map((s) => {
        const len = (s.value / sum) * circ;
        const el = <circle key={s.label} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={s.color}
          strokeWidth={stroke} strokeDasharray={`${len} ${circ - len}`} strokeDashoffset={-offset} />;
        offset += len; return el;
      })}
      <text x="50%" y="50%" transform={`rotate(90 ${size / 2} ${size / 2})`} textAnchor="middle" dominantBaseline="central" fontSize="20" fontWeight="800" fill="#0f172a">{total}</text>
    </svg>
  );
}
function Stat({ label, value, suffix = "" }) {
  return (
    <div className="rounded-xl bg-white/50 p-3 ring-1 ring-white/50">
      <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
      <p className="text-xl font-extrabold text-slate-800">{value}{suffix}</p>
    </div>
  );
}
