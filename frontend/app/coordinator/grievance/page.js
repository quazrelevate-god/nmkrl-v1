"use client";

/**
 * Coordinator Grievance page — adapts the citizen /map layout for staff.
 * Differences vs citizen:
 *   • Two dropdowns above the tab bar: Constituency (disabled-looking custom
 *     dropdown) + Ward (standard select). Ward list filters to the wards the
 *     chosen constituency covers (from CHENNAI_AC_MAP).
 *   • "In My Ward" list shows ward grievances with a "Verify Grievance"
 *     button per card; clicking it moves the grievance to the coordinator's
 *     "My Reports" tab and persists in local state.
 *   • "My Reports" shows the coordinator's verified grievances with 4 action
 *     buttons: Department Transfer / Redirect / Close / False Petition
 *     (instead of the citizen lifecycle tracker).
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import dynamic from "next/dynamic";
import {
  ThumbsUp, MapPin, RotateCcw, Ticket, Sparkles, Navigation,
  Search, X, Users, FileText, Landmark, ChevronDown, ChevronUp,
  ShieldCheck, Send, ArrowRightLeft, CheckCircle2, Ban, Check,
} from "lucide-react";
import CoordinatorShell from "@/components/coordinator/CoordinatorShell";
import { useCoordinator } from "@/components/coordinator/CoordinatorProvider";
import { fetchBoundaries, fetchWardIssues, adminCloseIssue, mediaUrl } from "@/lib/api";
import { statusMeta, STATUS_META } from "@/lib/status";
import { ticketNumber } from "@/lib/ticket";
import { haversineKm } from "@/lib/geo";
import { CHENNAI_AC_MAP, CONSTITUENCIES, shortAC } from "@/lib/constituencies";
import { departmentMeta } from "@/lib/departments";
import {
  RedirectModal, CloseModal, TransferModal, FalsePetitionModal,
} from "@/components/coordinator/ActionModals";

const MapView = dynamic(() => import("@/components/MapView"), {
  ssr: false,
  loading: () => (<div className="flex h-full w-full items-center justify-center bg-slate-100 text-sm text-slate-400">Loading map…</div>),
});

const RADIUS = 1500;

/* ── Grievance card used in BOTH tabs (with a slot for actions) ── */
function GrievanceCard({ issue, expanded, onToggle, dist, actions }) {
  const m = statusMeta(issue.status);
  return (
    <article className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
      <button onClick={onToggle} className="flex w-full items-center gap-3 p-3 text-left">
        {issue.image_url
          ? <img src={mediaUrl(issue.image_url)} alt="" className="h-10 w-10 shrink-0 rounded-lg object-cover" />
          : <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-lg">🛣️</div>}
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-bold leading-tight text-slate-900 truncate">{issue.title}</h3>
          <div className="mt-0.5 flex items-center gap-3 text-[11px] text-slate-400">
            <span className="flex items-center gap-1"><ThumbsUp size={10} /> {issue.upvotes}</span>
            {dist != null && (
              <span className="flex items-center gap-1"><Navigation size={10} />
                {dist < 1 ? `${Math.round(dist * 1000)} m` : `${dist.toFixed(1)} km`}
              </span>
            )}
            <span className={`rounded-full px-1.5 py-0.5 text-[9px] font-semibold ${m.badge}`}>{m.label}</span>
          </div>
        </div>
        {expanded ? <ChevronUp size={16} className="shrink-0 text-slate-400" />
          : <ChevronDown size={16} className="shrink-0 text-slate-400" />}
      </button>

      {expanded && (
        <div className="border-t border-slate-100 px-3 pb-3 pt-2 space-y-3">
          <div className="flex gap-3">
            {issue.image_url && (
              <img src={mediaUrl(issue.image_url)} alt="issue" className="h-24 w-24 shrink-0 rounded-xl object-cover" />
            )}
            <div className="min-w-0 flex-1 space-y-1">
              {issue.area_name && (
                <p className="flex items-center gap-1 text-[11px] text-slate-500">
                  <MapPin size={10} /> {issue.area_name}
                </p>
              )}
              <div className="flex flex-wrap items-center gap-1.5">
                <div className="inline-flex items-center gap-1 rounded bg-slate-100 px-1.5 py-0.5 font-mono text-[10px] font-semibold text-slate-500">
                  <Ticket size={9} /> {ticketNumber(issue.id)}
                </div>
                {issue.ward_no != null && (
                  <span className="rounded bg-brand-50 px-1.5 py-0.5 text-[10px] font-semibold text-brand-700 ring-1 ring-brand-200">
                    Ward {issue.ward_no}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-3 text-[11px] text-slate-400">
                <span className="flex items-center gap-1"><ThumbsUp size={10} /> {issue.upvotes}</span>
                <span>{new Date(issue.created_at).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}</span>
              </div>
            </div>
          </div>

          {(issue.transcript || (issue.summary_highlights?.length > 0)) && (
            <div className="rounded-xl bg-brand-50 border border-brand-100 p-2.5">
              <div className="flex items-center gap-1.5 mb-1.5">
                <Sparkles size={12} className="text-brand" />
                <span className="text-[10px] font-bold text-brand uppercase tracking-wide">AI Summary</span>
              </div>
              {issue.transcript && (
                <p className="text-xs italic text-slate-700 leading-snug mb-1.5">"{issue.transcript}"</p>
              )}
              {issue.summary_highlights?.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {issue.summary_highlights.map((h, i) => (
                    <span key={i} className="rounded-full bg-white px-2 py-0.5 text-[10px] font-medium text-brand ring-1 ring-brand-200">{h}</span>
                  ))}
                </div>
              )}
            </div>
          )}

          {actions}
        </div>
      )}
    </article>
  );
}

/* ── The "disabled looking" custom constituency dropdown ── */
function ConstituencyDropdown({ value, onChange, options }) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef(null);
  useEffect(() => {
    const close = (e) => { if (!rootRef.current?.contains(e.target)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);
  return (
    <div ref={rootRef} className="relative">
      {/* Disabled-look button (opacity + slate hues) that IS clickable */}
      <button onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between gap-2 rounded-xl bg-slate-100 px-3 py-2.5 text-left text-sm ring-1 ring-slate-200">
        <span className="flex items-center gap-1.5 text-slate-500">
          <Landmark size={13} className="opacity-70" />
          <span className="text-[11px] font-bold uppercase tracking-widest opacity-70">Constituency</span>
        </span>
        <span className="flex items-center gap-1.5">
          <span className="max-w-[160px] truncate text-[13px] font-semibold text-slate-500 opacity-80">
            {value ? shortAC(value) : "Choose"}
          </span>
          <ChevronDown size={14} className="text-slate-400 opacity-70" />
        </span>
      </button>
      {open && (
        <div className="animate-fade-up absolute inset-x-0 top-full z-30 mt-1 max-h-56 overflow-y-auto rounded-xl bg-white shadow-xl ring-1 ring-slate-200">
          {options.map((c) => (
            <button key={c} onClick={() => { onChange(c); setOpen(false); }}
              className={`flex w-full items-center justify-between px-3 py-2 text-left text-xs font-semibold hover:bg-slate-50 ${
                c === value ? "bg-brand-50 text-brand" : "text-slate-600"
              }`}>
              <span>{c}</span>
              {c === value && <Check size={13} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export default function CoordinatorGrievancePage() {
  const { me, state, actions, verify, flagFalse, addAction, hasActioned } = useCoordinator();

  const [center, setCenter] = useState(null);
  const [wardIssues, setWardIssues] = useState([]);
  const [selected, setSelected] = useState(null);
  const [query, setQuery] = useState("");
  const [boundaries, setBoundaries] = useState(null);
  const [tab, setTab] = useState("ward");
  const [expandedId, setExpandedId] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState(null);
  const [toast, setToast] = useState(null);

  // Modal targets (one at a time).
  const [redirectTarget, setRedirectTarget] = useState(null);
  const [closeTarget, setCloseTarget] = useState(null);
  const [transferTarget, setTransferTarget] = useState(null);
  const [falseTarget, setFalseTarget] = useState(null);

  // Constituency + ward selection (initialised from the signed-in coordinator).
  const [constituency, setConstituency] = useState(me?.constituency || "20 - Anna Nagar");
  const [ward, setWard] = useState(me?.homeWard || "103");

  useEffect(() => { fetchBoundaries().then(setBoundaries).catch(() => {}); }, []);

  // Ward list restricted to the chosen constituency (from CHENNAI_AC_MAP).
  const wardsInConstituency = useMemo(() => {
    const list = CHENNAI_AC_MAP[constituency] || [];
    return [...list].sort((a, b) => Number(a) - Number(b));
  }, [constituency]);

  // Ensure the current ward is valid for the chosen constituency.
  useEffect(() => {
    if (!wardsInConstituency.includes(ward)) {
      setWard(wardsInConstituency[0] || "");
    }
  }, [constituency, wardsInConstituency, ward]);

  // Recentre the map on the ward centroid whenever it changes.
  useEffect(() => {
    if (!boundaries || !ward) return;
    const feat = boundaries.wards?.features?.find((f) => String(f.properties.ward) === String(ward));
    if (!feat) return;
    const pts = [];
    const walk = (a) => { if (typeof a[0] === "number") pts.push(a); else a.forEach(walk); };
    walk(feat.geometry.coordinates);
    if (!pts.length) return;
    const lng = pts.reduce((s, c) => s + c[0], 0) / pts.length;
    const lat = pts.reduce((s, c) => s + c[1], 0) / pts.length;
    setCenter({ lat, lng });
  }, [ward, boundaries]);

  // Load grievances for the selected ward.
  const loadWard = useCallback(async (w) => {
    if (!w) return;
    try {
      const data = await fetchWardIssues(w);
      setWardIssues(data.issues || []);
    } catch { /* leave as-is */ }
  }, []);

  useEffect(() => { loadWard(ward); }, [ward, loadWard]);

  // Split ward issues into "In this ward" (not-yet verified) vs "My Reports" (this coordinator has verified).
  const verifiedIds = state?.verifiedIds || [];
  const falseIds = state?.falsePetitionIds || [];

  const wardIssuesFiltered = useMemo(() => {
    return wardIssues.filter((i) => !verifiedIds.includes(i.id) && !falseIds.includes(i.id));
  }, [wardIssues, verifiedIds, falseIds]);

  // Actioned grievances (redirected/closed/transferred/false) are excluded
  // from My Reports — they now live in the admin petition-list sections.
  const actionedIds = useMemo(() => new Set(actions.map((a) => a.issueId)), [actions]);

  const myReports = useMemo(() => {
    return wardIssues.filter((i) => verifiedIds.includes(i.id) && !actionedIds.has(i.id));
  }, [wardIssues, verifiedIds, actionedIds]);

  const publicIssues = useMemo(() => {
    // Map pins depend on the active tab.
    return tab === "mine" ? myReports : wardIssuesFiltered;
  }, [tab, wardIssuesFiltered, myReports]);

  const filteredMapIssues = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return publicIssues;
    return publicIssues.filter((i) =>
      ticketNumber(i.id).toLowerCase().includes(q) ||
      (i.title || "").toLowerCase().includes(q) ||
      (i.area_name || "").toLowerCase().includes(q));
  }, [query, publicIssues]);

  const currentWardNum = Number(ward) || null;
  const meta = selected ? statusMeta(selected.status) : null;

  function distanceKm(issue) {
    if (!center) return null;
    return haversineKm(center.lat, center.lng, issue.latitude, issue.longitude);
  }

  function toggleExpand(id) { setExpandedId((p) => (p === id ? null : id)); }

  function showToast(t) { setToast(t); setTimeout(() => setToast(null), 2400); }

  function handleVerify(issue) {
    verify(issue.id);
    showToast(`Verified · ${issue.title.slice(0, 30)} moved to My Reports`);
    setExpandedId(null);
  }

  /* ── Redirect ── */
  function submitRedirect(data) {
    const issue = redirectTarget;
    if (!issue) return;
    addAction({
      issueId: issue.id, kind: "redirect", issueTitle: issue.title,
      wardNo: issue.ward_no, department: issue.department, data,
    });
    setRedirectTarget(null);
    setExpandedId(null);
    showToast("Redirected to admin");
  }

  /* ── Transfer ── */
  function submitTransfer(data) {
    const issue = transferTarget;
    if (!issue) return;
    addAction({
      issueId: issue.id, kind: "transfer", issueTitle: issue.title,
      wardNo: issue.ward_no, department: data.department, data,
    });
    setTransferTarget(null);
    setExpandedId(null);
    showToast(`Transferred to ${departmentMeta(data.department).short}`);
  }

  /* ── Close (photo + voice mandatory) ── */
  async function submitClose(data) {
    const issue = closeTarget;
    if (!issue) return;
    setBusyId(issue.id);
    try {
      await adminCloseIssue(issue.id);
      addAction({
        issueId: issue.id, kind: "close", issueTitle: issue.title,
        wardNo: issue.ward_no, department: issue.department, data,
      });
      showToast("Closed · awaiting citizen verification");
      setCloseTarget(null);
      setExpandedId(null);
      await loadWard(ward);
    } catch (err) {
      setError(err.message);
    } finally { setBusyId(null); }
  }

  /* ── False Petition ── */
  function submitFalse(data) {
    const issue = falseTarget;
    if (!issue) return;
    flagFalse(issue.id);
    addAction({
      issueId: issue.id, kind: "false", issueTitle: issue.title,
      wardNo: issue.ward_no, department: issue.department, data,
    });
    setFalseTarget(null);
    setExpandedId(null);
    showToast("Flagged as false petition");
  }

  return (
    <CoordinatorShell noPad splitView>
      {/* Map top 40% */}
      <div className="relative shrink-0" style={{ height: "40%" }}>
        <MapView
          center={center}
          issues={filteredMapIssues}
          radius={RADIUS}
          selectedId={selected?.id}
          onSelect={setSelected}
          boundaries={boundaries}
          currentWard={currentWardNum}
        />

        {/* Search bar */}
        <div className="absolute left-0 right-0 top-0 z-[400] px-3 pt-2">
          <div className="flex items-center gap-2 rounded-xl bg-white/95 px-3 py-2 shadow ring-1 ring-slate-200">
            <Search size={15} className="shrink-0 text-slate-400" />
            <input value={query} onChange={(e) => setQuery(e.target.value)}
              placeholder="Search grievances in this ward"
              className="min-w-0 flex-1 bg-transparent text-xs outline-none placeholder:text-slate-400" />
            {query && <button onClick={() => setQuery("")} className="shrink-0 text-slate-400"><X size={14} /></button>}
          </div>
        </div>

        {/* Status legend */}
        <div className="absolute bottom-2 left-2 z-[400] flex flex-col gap-0.5 rounded-xl bg-white/90 p-1.5 text-[9px] shadow ring-1 ring-slate-200">
          {Object.entries(STATUS_META).filter(([k]) => k !== "SUBMITTED").map(([key, m]) => (
            <span key={key} className="flex items-center gap-1">
              <span className="inline-block h-2 w-2 rounded-full" style={{ background: m.pin }} />
              {m.label}
            </span>
          ))}
        </div>

        {/* Selected grievance sheet */}
        {selected && (
          <div className="absolute bottom-0 left-0 right-0 z-[450] rounded-t-2xl bg-white p-3 shadow-2xl">
            <div className="flex gap-3">
              {selected.image_url
                ? <img src={mediaUrl(selected.image_url)} alt="" className="h-16 w-16 rounded-xl object-cover" />
                : <div className="flex h-16 w-16 items-center justify-center rounded-xl bg-slate-100 text-2xl">🛣️</div>}
              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-1">
                  <p className="text-sm font-bold text-slate-900 leading-tight">{selected.title}</p>
                  <button onClick={() => setSelected(null)} className="text-slate-400 shrink-0">✕</button>
                </div>
                {selected.area_name && <p className="text-xs text-slate-500">{selected.area_name}</p>}
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <span className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold ${meta.badge}`}>{meta.label}</span>
                  <span className="font-mono text-[10px] font-semibold text-slate-400">{ticketNumber(selected.id)}</span>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Bottom pane */}
      <div className="no-scrollbar flex-1 overflow-y-auto bg-slate-50 px-4 pt-3 pb-28">
        {/* Constituency + ward selectors */}
        <div className="mb-3 space-y-2">
          <ConstituencyDropdown value={constituency} onChange={setConstituency} options={CONSTITUENCIES} />
          <div className="relative">
            <label className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-slate-400">Ward</label>
            <select value={ward} onChange={(e) => setWard(e.target.value)}
              className="w-full appearance-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 pr-9 text-sm font-semibold text-slate-800 outline-none focus:border-brand">
              {wardsInConstituency.length === 0 && <option value="">No wards mapped</option>}
              {wardsInConstituency.map((w) => (<option key={w} value={w}>Ward {w}</option>))}
            </select>
            <ChevronDown size={14} className="pointer-events-none absolute right-3 top-[38px] text-slate-400" />
          </div>
        </div>

        {/* Tabs */}
        <div className="mb-3 flex gap-1 rounded-xl bg-slate-200/70 p-1">
          <button onClick={() => setTab("ward")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${
              tab === "ward" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"
            }`}>
            <Users size={13} /> In This Ward ({wardIssuesFiltered.length})
          </button>
          <button onClick={() => setTab("mine")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${
              tab === "mine" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"
            }`}>
            <FileText size={13} /> My Reports ({myReports.length})
          </button>
        </div>

        {error && (
          <p className="mb-3 rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">{error}</p>
        )}

        {/* ── IN THIS WARD ── */}
        {tab === "ward" && (
          <>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-extrabold text-slate-900">
                Public grievances in Ward {ward || "—"}
              </h2>
              <button onClick={() => loadWard(ward)} className="flex items-center gap-1 text-xs font-medium text-brand">
                <RotateCcw size={12} /> Refresh
              </button>
            </div>
            {wardIssuesFiltered.length === 0 ? (
              <div className="py-10 text-center text-sm text-slate-400">
                <Users size={32} className="mx-auto mb-2 text-slate-300" />
                No unverified grievances in Ward {ward}.
              </div>
            ) : (
              <div className="space-y-2">
                {wardIssuesFiltered.map((issue) => (
                  <GrievanceCard
                    key={issue.id}
                    issue={issue}
                    expanded={expandedId === issue.id}
                    onToggle={() => toggleExpand(issue.id)}
                    dist={distanceKm(issue)}
                    actions={
                      <button onClick={() => handleVerify(issue)}
                        className="flex w-full items-center justify-center gap-1.5 rounded-xl bg-brand py-2.5 text-xs font-bold text-white">
                        <ShieldCheck size={13} /> Verify Grievance
                      </button>
                    }
                  />
                ))}
              </div>
            )}
          </>
        )}

        {/* ── MY REPORTS ── */}
        {tab === "mine" && (
          <>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-extrabold text-slate-900">Verified by me</h2>
              <button onClick={() => loadWard(ward)} className="flex items-center gap-1 text-xs font-medium text-brand">
                <RotateCcw size={12} /> Refresh
              </button>
            </div>
            {myReports.length === 0 ? (
              <div className="py-10 text-center text-sm text-slate-400">
                <FileText size={32} className="mx-auto mb-2 text-slate-300" />
                Verify grievances from the ward tab to see them here.
              </div>
            ) : (
              <div className="space-y-2">
                {myReports.map((issue) => (
                  <GrievanceCard
                    key={issue.id}
                    issue={issue}
                    expanded={expandedId === issue.id}
                    onToggle={() => toggleExpand(issue.id)}
                    dist={distanceKm(issue)}
                    actions={
                      <div className="grid grid-cols-2 gap-2">
                        <button onClick={() => setTransferTarget(issue)}
                          className="flex items-center justify-center gap-1.5 rounded-lg bg-brand py-2 text-[11px] font-bold text-white">
                          <Send size={12} /> Dept. Transfer
                        </button>
                        <button onClick={() => setRedirectTarget(issue)}
                          className="flex items-center justify-center gap-1.5 rounded-lg bg-slate-800 py-2 text-[11px] font-bold text-white">
                          <ArrowRightLeft size={12} /> Redirect
                        </button>
                        <button onClick={() => setCloseTarget(issue)}
                          className="flex items-center justify-center gap-1.5 rounded-lg bg-emerald-600 py-2 text-[11px] font-bold text-white">
                          <CheckCircle2 size={12} /> Close
                        </button>
                        <button onClick={() => setFalseTarget(issue)}
                          className="flex items-center justify-center gap-1.5 rounded-lg border border-rose-200 bg-white py-2 text-[11px] font-bold text-rose-600">
                          <Ban size={12} /> False Petition
                        </button>
                      </div>
                    }
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {toast && (
        <div className="pointer-events-none absolute inset-x-0 bottom-24 z-[720] flex justify-center px-4">
          <div className="pointer-events-auto rounded-full bg-slate-900/90 px-4 py-2 text-xs font-semibold text-white shadow-lg backdrop-blur">
            {toast}
          </div>
        </div>
      )}

      <RedirectModal open={!!redirectTarget} issue={redirectTarget}
        onClose={() => setRedirectTarget(null)} onSubmit={submitRedirect} />
      <TransferModal open={!!transferTarget} issue={transferTarget}
        onClose={() => setTransferTarget(null)} onSubmit={submitTransfer} />
      <CloseModal open={!!closeTarget} issue={closeTarget}
        onClose={() => setCloseTarget(null)} onSubmit={submitClose} />
      <FalsePetitionModal open={!!falseTarget} issue={falseTarget}
        onClose={() => setFalseTarget(null)} onSubmit={submitFalse} />
    </CoordinatorShell>
  );
}
