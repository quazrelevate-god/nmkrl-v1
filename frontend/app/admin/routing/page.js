"use client";

/**
 * Department Routing
 * ------------------
 * Departmental-level resolution tracking. Every grievance is routed (via the AI
 * taxonomy) to a Government Department; this page aggregates the live ticket
 * data by department so staff can see where volume concentrates, how each
 * department is performing (resolution rate, SLA breaches, ageing) and whether
 * its responsible-officer contacts are configured.
 */

import { useEffect, useMemo, useState } from "react";
import {
  Network, Building2, TrendingUp, TimerOff, Gauge, Contact, Layers,
  ClipboardList, CheckCircle2, Loader,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import { slaBreached, daysOpen } from "@/lib/adminModel";
import {
  loadDeptTree, resolveRouting, deptOfficerCount, loadContacts, contactKey, deptOfficerGroups,
} from "@/lib/deptRouting";

const RESOLVED = ["PENDING_VERIFICATION", "CLOSED"];
const INPROG = ["IN_PROGRESS"];
const OPEN = ["SUBMITTED", "ACTIVE", "FORWARDED"];

export default function RoutingPage() {
  const { issues, loading } = useAdminData();
  const [tree, setTree] = useState(null);
  const [contacts, setContacts] = useState({});

  useEffect(() => {
    loadDeptTree().then(setTree);
    setContacts(loadContacts());
    const sync = () => setContacts(loadContacts());
    window.addEventListener("nk:dept-contacts-changed", sync);
    return () => window.removeEventListener("nk:dept-contacts-changed", sync);
  }, []);

  const stats = useMemo(() => {
    if (!tree || !issues?.length) return [];
    const byDept = new Map();
    for (const it of issues) {
      const r = resolveRouting(it, tree);
      if (!r) continue;
      if (!byDept.has(r.govDept)) byDept.set(r.govDept, { dept: r.govDept, total: 0, open: 0, inProgress: 0, resolved: 0, breached: 0, ageSum: 0, ageN: 0, subDepts: new Map() });
      const s = byDept.get(r.govDept);
      s.total++;
      if (RESOLVED.includes(it.status)) s.resolved++;
      else if (INPROG.includes(it.status)) s.inProgress++;
      else s.open++;
      if (slaBreached(it)) s.breached++;
      if (!RESOLVED.includes(it.status)) { s.ageSum += daysOpen(it); s.ageN++; }
      s.subDepts.set(r.subDept, (s.subDepts.get(r.subDept) || 0) + 1);
    }
    // enrich with coverage
    const arr = [...byDept.values()].map((s) => {
      const total = deptOfficerCount(tree, s.dept);
      let done = 0;
      for (const g of deptOfficerGroups(tree, s.dept))
        for (const o of g.officers) {
          const c = contacts[contactKey(s.dept, g.subDept, o)];
          if (c && c.name && c.mobile) done++;
        }
      const topSub = [...s.subDepts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || "—";
      return {
        ...s,
        rate: s.total ? Math.round((s.resolved / s.total) * 100) : 0,
        avgAge: s.ageN ? Math.round(s.ageSum / s.ageN) : 0,
        coverage: total ? Math.round((done / total) * 100) : 0,
        coverageDone: done, coverageTotal: total,
        topSub,
      };
    });
    return arr.sort((a, b) => b.total - a.total);
  }, [tree, issues, contacts]);

  const totals = useMemo(() => {
    const t = stats.reduce((a, s) => ({
      grievances: a.grievances + s.total,
      resolved: a.resolved + s.resolved,
      breached: a.breached + s.breached,
      ageSum: a.ageSum + s.ageSum, ageN: a.ageN + s.ageN,
      covDone: a.covDone + s.coverageDone, covTotal: a.covTotal + s.coverageTotal,
    }), { grievances: 0, resolved: 0, breached: 0, ageSum: 0, ageN: 0, covDone: 0, covTotal: 0 });
    return {
      depts: stats.length,
      grievances: t.grievances,
      rate: t.grievances ? Math.round((t.resolved / t.grievances) * 100) : 0,
      avgAge: t.ageN ? Math.round(t.ageSum / t.ageN) : 0,
      breached: t.breached,
      coverage: t.covTotal ? Math.round((t.covDone / t.covTotal) * 100) : 0,
    };
  }, [stats]);

  return (
    <>
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand"><Network size={20} /></div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Department Routing</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Resolution tracking by government department</p>
          </div>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5 space-y-5">
        {loading || !tree ? (
          <p className="flex items-center justify-center gap-2 py-16 text-sm text-slate-400"><Loader size={16} className="animate-spin" /> Loading routing analytics…</p>
        ) : stats.length === 0 ? (
          <p className="py-16 text-center text-sm text-slate-400">No grievances to route yet.</p>
        ) : (
          <>
            {/* Summary KPIs */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <Kpi icon={Building2} label="Departments" value={totals.depts} tone="text-brand" />
              <Kpi icon={ClipboardList} label="Grievances Routed" value={totals.grievances} tone="text-slate-800" />
              <Kpi icon={TrendingUp} label="Resolution Rate" value={`${totals.rate}%`} tone="text-emerald-600" />
              <Kpi icon={Gauge} label="Avg Ageing" value={`${totals.avgAge}d`} tone="text-amber-600" />
              <Kpi icon={TimerOff} label="SLA Breached" value={totals.breached} tone="text-rose-500" />
              <Kpi icon={Contact} label="Officer Coverage" value={`${totals.coverage}%`} tone="text-violet-600" />
            </div>

            {/* Per-department cards */}
            <p className="flex items-center gap-2 pt-1 text-sm font-extrabold text-slate-700"><Layers size={16} className="text-brand" /> By government department</p>
            <div className="space-y-3">
              {stats.map((s) => <DeptCard key={s.dept} s={s} />)}
            </div>
          </>
        )}
      </div>
    </>
  );
}

function DeptCard({ s }) {
  const openPct = s.total ? (s.open / s.total) * 100 : 0;
  const ipPct = s.total ? (s.inProgress / s.total) * 100 : 0;
  const resPct = s.total ? (s.resolved / s.total) * 100 : 0;
  return (
    <div className="glass-panel rounded-2xl p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-brand/10 text-brand"><Building2 size={20} /></div>
          <div className="min-w-0">
            <p className="text-sm font-extrabold leading-tight text-slate-900">{s.dept}</p>
            <p className="text-[11px] text-slate-400">Top sub-dept · {s.topSub}</p>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <Metric label="Volume" value={s.total} />
          <Metric label="Resolved" value={`${s.rate}%`} tone="text-emerald-600" />
          <Metric label="Ageing" value={`${s.avgAge}d`} tone="text-amber-600" />
          <Metric label="SLA breach" value={s.breached} tone={s.breached ? "text-rose-500" : "text-slate-700"} />
          <div className="text-center">
            <CovRing pct={s.coverage} />
            <p className="mt-0.5 text-[9px] font-bold uppercase tracking-wide text-slate-400">Coverage</p>
          </div>
        </div>
      </div>

      {/* status breakdown bar */}
      <div className="mt-3">
        <div className="flex h-2.5 overflow-hidden rounded-full bg-slate-100">
          <span className="bg-amber-400" style={{ width: `${openPct}%` }} title={`Open ${s.open}`} />
          <span className="bg-violet-500" style={{ width: `${ipPct}%` }} title={`In progress ${s.inProgress}`} />
          <span className="bg-emerald-500" style={{ width: `${resPct}%` }} title={`Resolved ${s.resolved}`} />
        </div>
        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-0.5 text-[10px] font-semibold">
          <span className="flex items-center gap-1 text-amber-600"><Dot c="#f59e0b" /> Open {s.open}</span>
          <span className="flex items-center gap-1 text-violet-600"><Dot c="#8b5cf6" /> In progress {s.inProgress}</span>
          <span className="flex items-center gap-1 text-emerald-600"><Dot c="#10b981" /> Resolved {s.resolved}</span>
        </div>
      </div>
    </div>
  );
}

function Kpi({ icon: Icon, label, value, tone }) {
  return (
    <div className="glass-panel rounded-2xl p-4">
      <div className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-400"><Icon size={12} /> {label}</div>
      <p className={`text-2xl font-extrabold ${tone}`}>{value}</p>
    </div>
  );
}

function Metric({ label, value, tone = "text-slate-800" }) {
  return (
    <div className="text-center">
      <p className={`text-lg font-extrabold leading-none ${tone}`}>{value}</p>
      <p className="mt-0.5 text-[9px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
    </div>
  );
}

function Dot({ c }) {
  return <span className="inline-block h-2 w-2 rounded-full" style={{ background: c }} />;
}

function CovRing({ pct }) {
  const r = 13, c = 2 * Math.PI * r;
  const color = pct >= 66 ? "#10b981" : pct >= 33 ? "#f59e0b" : "#ef4444";
  return (
    <svg width="34" height="34" viewBox="0 0 34 34" className="-rotate-90">
      <circle cx="17" cy="17" r={r} fill="none" strokeWidth="4" stroke="#e2e8f0" />
      <circle cx="17" cy="17" r={r} fill="none" strokeWidth="4" strokeLinecap="round" stroke={color} strokeDasharray={`${(pct / 100) * c} ${c}`} />
      <text x="17" y="17" transform="rotate(90 17 17)" textAnchor="middle" dominantBaseline="central" fontSize="9" fontWeight="800" fill="#334155">{pct}%</text>
    </svg>
  );
}
