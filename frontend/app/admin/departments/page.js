"use client";

/**
 * Departmental Configuration
 * --------------------------
 * Staff manually enter the real name + mobile number of the Responsible Officer
 * behind every Sub Department, for each Government Department in the grievance
 * taxonomy. These contacts are what the ticket routing resolves to.
 *
 * Layout: a searchable rail of Government Departments (with a configured/total
 * progress ring) on the left; the selected department's officers — grouped by
 * Sub Department — as name/mobile rows on the right. Everything autosaves to
 * localStorage. A "Bulk import (CSV)" affordance is shown but non-functional.
 */

import { useEffect, useMemo, useState } from "react";
import {
  FolderTree, Search, Upload, UserCog, Phone, Building2, CheckCircle2,
  ChevronRight, ShieldCheck,
} from "lucide-react";
import {
  loadDeptTree, govDepartments, deptOfficerGroups, deptOfficerCount,
  loadContacts, saveContacts, contactKey,
} from "@/lib/deptRouting";

export default function DepartmentsPage() {
  const [tree, setTree] = useState(null);
  const [selected, setSelected] = useState(null);
  const [query, setQuery] = useState("");
  const [contacts, setContacts] = useState({});

  useEffect(() => {
    loadDeptTree().then((t) => {
      setTree(t);
      const list = govDepartments(t);
      setSelected((s) => s || list[0] || null);
    });
    setContacts(loadContacts());
  }, []);

  const departments = useMemo(() => (tree ? govDepartments(tree) : []), [tree]);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? departments.filter((d) => d.toLowerCase().includes(q)) : departments;
  }, [departments, query]);

  const groups = useMemo(
    () => (tree && selected ? deptOfficerGroups(tree, selected) : []),
    [tree, selected]
  );

  // configured count for a department (memo-free helper; cheap)
  function configuredCount(deptName) {
    if (!tree) return { done: 0, total: 0 };
    const gs = deptOfficerGroups(tree, deptName);
    let done = 0, total = 0;
    for (const g of gs) for (const o of g.officers) {
      total++;
      const c = contacts[contactKey(deptName, g.subDept, o)];
      if (c && c.name && c.mobile) done++;
    }
    return { done, total };
  }

  function update(deptName, subDept, officer, field, value) {
    const key = contactKey(deptName, subDept, officer);
    setContacts((prev) => {
      const next = { ...prev, [key]: { ...(prev[key] || {}), [field]: value } };
      saveContacts(next);
      return next;
    });
  }

  const selCount = selected ? configuredCount(selected) : { done: 0, total: 0 };
  const selPct = selCount.total ? Math.round((selCount.done / selCount.total) * 100) : 0;

  return (
    <>
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand"><FolderTree size={20} /></div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Departmental Configuration</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Responsible officer contacts · {departments.length} departments</p>
          </div>
        </div>
        <button
          title="Bulk import officer contacts from a CSV (demo)"
          className="flex items-center gap-2 rounded-xl border border-slate-300 bg-white/70 px-3.5 py-2 text-xs font-bold text-slate-600 hover:-translate-y-px hover:bg-white"
          style={{ transition: "all .25s ease" }}
        >
          <Upload size={14} /> Bulk import (CSV)
        </button>
      </header>

      <div className="flex min-h-0 flex-1 overflow-hidden">
        {/* ── Department rail ── */}
        <aside className="flex w-72 shrink-0 flex-col border-r border-white/50 bg-white/25">
          <div className="p-3">
            <div className="glass-panel flex items-center gap-2 rounded-xl px-3 py-2">
              <Search size={14} className="text-slate-400" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search departments"
                className="min-w-0 flex-1 bg-transparent text-xs outline-none placeholder:text-slate-400"
              />
            </div>
          </div>
          <div className="no-scrollbar min-h-0 flex-1 overflow-y-auto px-2 pb-3">
            {filtered.map((d) => {
              const { done, total } = configuredCount(d);
              const pct = total ? Math.round((done / total) * 100) : 0;
              const active = d === selected;
              return (
                <button
                  key={d}
                  onClick={() => setSelected(d)}
                  className={`mb-1 flex w-full items-center gap-2.5 rounded-xl px-3 py-2.5 text-left transition ${
                    active ? "bg-gradient-to-r from-brand to-brand-dark text-white shadow" : "hover:bg-slate-900/5"
                  }`}
                >
                  <Ring pct={pct} active={active} />
                  <div className="min-w-0 flex-1">
                    <p className={`truncate text-[12.5px] font-bold ${active ? "text-white" : "text-slate-700"}`}>{shortDept(d)}</p>
                    <p className={`text-[10px] font-medium ${active ? "text-white/70" : "text-slate-400"}`}>{done}/{total} officers set</p>
                  </div>
                  <ChevronRight size={14} className={active ? "text-white/70" : "text-slate-300"} />
                </button>
              );
            })}
          </div>
        </aside>

        {/* ── Officer form ── */}
        <div className="no-scrollbar min-h-0 flex-1 overflow-y-auto px-7 py-5">
          {!selected ? (
            <p className="py-16 text-center text-sm text-slate-400">Loading departments…</p>
          ) : (
            <>
              {/* selected dept summary */}
              <div className="glass-panel mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl px-5 py-4">
                <div className="flex items-center gap-3">
                  <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-brand/10 text-brand"><Building2 size={22} /></div>
                  <div>
                    <h2 className="text-base font-extrabold text-slate-900">{selected}</h2>
                    <p className="text-xs text-slate-500">{groups.length} sub-departments · {selCount.total} responsible officers</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-2xl font-black text-brand">{selPct}%</p>
                  <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{selCount.done}/{selCount.total} configured</p>
                </div>
              </div>

              {/* groups */}
              <div className="space-y-5">
                {groups.map((g) => (
                  <section key={g.subDept} className="glass-panel rounded-2xl p-4">
                    <p className="mb-3 flex items-center gap-1.5 text-sm font-bold text-slate-700">
                      <Building2 size={14} className="text-brand" /> {g.subDept}
                      <span className="ml-1 rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-bold text-slate-500">{g.officers.length}</span>
                    </p>
                    <div className="space-y-2.5">
                      {g.officers.map((officer) => {
                        const c = contacts[contactKey(selected, g.subDept, officer)] || {};
                        const filled = c.name && c.mobile;
                        return (
                          <div key={officer} className="grid grid-cols-1 items-center gap-2 rounded-xl bg-white/60 p-2.5 ring-1 ring-white/60 md:grid-cols-[1.4fr_1fr_1fr_auto]">
                            <div className="flex items-center gap-2">
                              <UserCog size={15} className="shrink-0 text-slate-400" />
                              <p className="text-[12.5px] font-semibold leading-tight text-slate-700">{officer}</p>
                            </div>
                            <input
                              value={c.name || ""}
                              onChange={(e) => update(selected, g.subDept, officer, "name", e.target.value)}
                              placeholder="Officer name"
                              className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand"
                            />
                            <div className="flex items-center rounded-lg border border-slate-200 bg-white focus-within:border-brand">
                              <span className="flex items-center gap-1 border-r border-slate-200 px-2 text-xs text-slate-400"><Phone size={11} /> +91</span>
                              <input
                                value={c.mobile || ""}
                                onChange={(e) => update(selected, g.subDept, officer, "mobile", e.target.value.replace(/\D/g, "").slice(0, 10))}
                                inputMode="numeric"
                                placeholder="Mobile number"
                                className="min-w-0 flex-1 rounded-r-lg bg-transparent px-2 py-2 text-sm outline-none"
                              />
                            </div>
                            <span className={`flex h-7 w-7 items-center justify-center rounded-full ${filled ? "bg-emerald-100 text-emerald-600" : "bg-slate-100 text-slate-300"}`}>
                              <CheckCircle2 size={16} />
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  </section>
                ))}
              </div>

              <p className="mt-5 flex items-center justify-center gap-1.5 text-[11px] italic text-slate-400">
                <ShieldCheck size={12} className="text-emerald-500" /> Contacts autosave locally · used by ticket routing &amp; WhatsApp dispatch
              </p>
            </>
          )}
        </div>
      </div>
    </>
  );
}

/* Trim the "(ABBR)" and "Department" noise for the rail's compact label. */
function shortDept(name) {
  return name.replace(/\s*\([^)]*\)\s*$/, "").replace(/\s+Department$/, "");
}

/* Small SVG progress ring for the rail. */
function Ring({ pct, active }) {
  const r = 9, c = 2 * Math.PI * r;
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" className="shrink-0 -rotate-90">
      <circle cx="12" cy="12" r={r} fill="none" strokeWidth="3" stroke={active ? "rgba(255,255,255,0.3)" : "#e2e8f0"} />
      <circle
        cx="12" cy="12" r={r} fill="none" strokeWidth="3" strokeLinecap="round"
        stroke={active ? "#f5d97a" : "#1a3556"}
        strokeDasharray={`${(pct / 100) * c} ${c}`}
      />
    </svg>
  );
}
