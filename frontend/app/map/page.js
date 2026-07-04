"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import {
  ThumbsUp, CheckCircle2, XCircle, MapPin, RotateCcw,
  SlidersHorizontal, Ticket, ChevronDown, ChevronUp, Sparkles, Navigation,
  Search, X, Users, FileText, Landmark,
} from "lucide-react";
import MobileShell from "@/components/MobileShell";
import UpvoteModal from "@/components/UpvoteModal";
import LocationDetector from "@/components/LocationDetector";
import {
  fetchNearby, fetchHistory, fetchBoundaries, fetchWardIssues,
  upvoteIssue, verifyIssue, mediaUrl,
} from "@/lib/api";
import { useGeolocation } from "@/lib/hooks";
import { getUserId } from "@/lib/user";
import { statusMeta, STATUS_META } from "@/lib/status";
import { ticketNumber } from "@/lib/ticket";
import { haversineKm } from "@/lib/geo";

const MapView = dynamic(() => import("@/components/MapView"), {
  ssr: false,
  loading: () => (
    <div className="flex h-full w-full items-center justify-center bg-slate-100 text-sm text-slate-400">
      Loading map…
    </div>
  ),
});

const RADIUS = 1500;
const LIFECYCLE = ["Submitted", "Pending Verification", "Assigned", "Inspection", "Repair", "Verification", "Completed"];

function progressIndex(status) {
  switch (status) {
    case "SUBMITTED":            return 1;
    case "ACTIVE":               return 2;
    case "IN_PROGRESS":          return 4;
    case "PENDING_VERIFICATION": return 5;
    case "CLOSED":               return 6;
    default:                     return 0;
  }
}

/* ── Reusable collapsible grievance card (My Reports + In My Ward) ── */
function IssueCard({ issue, expanded, onToggle, dist, onUpvote }) {
  const m  = statusMeta(issue.status);
  const pi = progressIndex(issue.status);
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
              <span className="flex items-center gap-1">
                <Navigation size={10} />
                {dist < 1 ? `${Math.round(dist * 1000)} m` : `${dist.toFixed(1)} km`}
              </span>
            )}
            <span className={`rounded-full px-1.5 py-0.5 text-[9px] font-semibold ${m.badge} ${
              (issue.status === "PENDING_VERIFICATION" || issue.status === "SUBMITTED") ? "glow-pending" : ""
            }`}>{m.label}</span>
          </div>
        </div>
        {expanded
          ? <ChevronUp size={16} className="shrink-0 text-slate-400" />
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
                  <span className="rounded bg-violet-50 px-1.5 py-0.5 text-[10px] font-semibold text-violet-700 ring-1 ring-violet-200">
                    Ward no: {issue.ward_no}
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

          {/* Lifecycle progress — current step glows */}
          <div className="flex items-start justify-between">
            {LIFECYCLE.map((step, idx) => {
              const done = idx < pi;
              const active = idx === pi;
              return (
                <div key={step} className="flex flex-1 flex-col items-center">
                  <div className="flex w-full items-center">
                    {idx > 0 && <div className={`h-0.5 flex-1 ${idx <= pi ? "bg-brand" : "bg-slate-200"}`} />}
                    <div className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full text-[8px] ${
                      active ? "glow-dot bg-amber-500 text-white ring-2 ring-amber-300"
                        : done ? "bg-brand text-white" : "bg-slate-200 text-slate-400"}`}>
                      {done ? "✓" : ""}
                    </div>
                    {idx < LIFECYCLE.length - 1 && <div className={`h-0.5 flex-1 ${idx < pi ? "bg-brand" : "bg-slate-200"}`} />}
                  </div>
                  <span className={`mt-1 flex h-6 items-start justify-center text-center text-[6px] leading-tight ${active ? "font-bold text-amber-600" : "text-slate-400"}`}>{step}</span>
                </div>
              );
            })}
          </div>

          {onUpvote && (
            <button
              onClick={() => onUpvote(issue)}
              className="flex w-full items-center justify-center gap-1.5 rounded-xl bg-brand py-2.5 text-xs font-bold text-white"
            >
              <ThumbsUp size={13} /> Support this grievance
            </button>
          )}
        </div>
      )}
    </article>
  );
}

export default function MapHistoryScreen() {
  const { coords: geoCoords } = useGeolocation();
  const [override, setOverride]   = useState(null); // demo: jump to an Egmore ward
  const coords = override || geoCoords;             // effective location
  const [center, setCenter]       = useState(null); // fixed device location
  const [mapIssues, setMapIssues] = useState([]);
  const [wardIssues, setWardIssues] = useState([]);
  const [selected, setSelected]   = useState(null);
  const [upvoteTarget, setUpvoteTarget] = useState(null);
  const [query, setQuery]         = useState("");
  const [boundaries, setBoundaries] = useState(null);
  const [tab, setTab]             = useState("ward"); // 'ward' | 'mine'

  const [userId, setUserId]       = useState("demo-user");
  const [history, setHistory]     = useState([]);
  const [histLoading, setHistLoading] = useState(true);
  const [busyId, setBusyId]       = useState(null);
  const [error, setError]         = useState(null);
  const [expandedId, setExpandedId] = useState(null);
  const [detected, setDetected]   = useState(null); // real GCC zone/ward from /api/locate

  useEffect(() => { setUserId(getUserId()); }, []);
  useEffect(() => { fetchBoundaries().then(setBoundaries).catch(() => {}); }, []);
  // Device location is captured once and stays fixed — the radius never drifts.
  useEffect(() => { if (coords && !center) setCenter(coords); }, [coords, center]);
  // Demo jump recenters the map on the chosen Egmore ward.
  useEffect(() => { if (override) setCenter(override); }, [override]);

  // Sneaky demo: our real GPS is outside GCC, so jump the detected location to
  // an Egmore ward so the ward-level grievance data can be visualised.
  function jumpToEgmore() {
    const EGMORE_WARDS = ["58", "61", "77", "78", "104", "108"];
    const feats = boundaries?.wards?.features || [];
    const f = feats.find((ft) => EGMORE_WARDS.includes(String(ft.properties.ward)));
    if (!f) return;
    const pts = [];
    const walk = (a) => { if (typeof a[0] === "number") pts.push(a); else a.forEach(walk); };
    walk(f.geometry.coordinates);
    const lng = pts.reduce((s, c) => s + c[0], 0) / pts.length;
    const lat = pts.reduce((s, c) => s + c[1], 0) / pts.length;
    setOverride({ lat, lng });
  }

  // The ward now comes from the real GCC boundary lookup (via LocationDetector →
  // /api/locate), not the deprecated client-side mock grid.
  const currentWard = useMemo(
    () => (detected?.inside && detected?.ward != null ? parseInt(detected.ward, 10) : null),
    [detected]
  );

  const loadMap = useCallback(async (c) => {
    if (!c) return;
    try {
      const data = await fetchNearby(c.lat, c.lng, RADIUS);
      setMapIssues(data.issues || []);
    } catch {}
  }, []);

  const loadWard = useCallback(async (w) => {
    if (w == null) return;
    try {
      const data = await fetchWardIssues(w);
      setWardIssues(data.issues || []);
    } catch {}
  }, []);

  const loadHistory = useCallback(async (uid) => {
    setHistLoading(true);
    try {
      const data = await fetchHistory(uid);
      setHistory(data.issues || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setHistLoading(false);
    }
  }, []);

  useEffect(() => { if (center) loadMap(center); }, [center, loadMap]);
  useEffect(() => { if (currentWard != null) loadWard(currentWard); }, [currentWard, loadWard]);
  useEffect(() => { loadHistory(userId); }, [userId, loadHistory]);

  // Public pins on the map = nearby (radius) ∪ ward grievances, deduped.
  const publicIssues = useMemo(() => {
    const map = new Map();
    for (const i of [...mapIssues, ...wardIssues]) map.set(i.id, i);
    return [...map.values()];
  }, [mapIssues, wardIssues]);

  // Search public grievances by ticket number, title or area.
  const filteredMapIssues = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return publicIssues;
    return publicIssues.filter(i =>
      ticketNumber(i.id).toLowerCase().includes(q) ||
      (i.title || "").toLowerCase().includes(q) ||
      (i.area_name || "").toLowerCase().includes(q)
    );
  }, [query, publicIssues]);

  async function confirmUpvote(name) {
    try {
      const updated = await upvoteIssue(upvoteTarget.id, userId, name);
      const apply = (arr) => arr.map(i => i.id === updated.id ? updated : i);
      setSelected(updated);
      setMapIssues(apply);
      setWardIssues(apply);
      setUpvoteTarget(null);
    } catch (err) {
      setError(err.message);
      setUpvoteTarget(null);
    }
  }

  async function handleVerify(issue, response) {
    setBusyId(issue.id);
    try {
      await verifyIssue(issue.id, userId, response);
      await loadHistory(userId);
      await loadMap(center);
      await loadWard(currentWard);
    } catch (err) { setError(err.message); }
    finally { setBusyId(null); }
  }

  function toggleExpand(id) {
    setExpandedId(prev => prev === id ? null : id);
  }

  function distanceKm(issue) {
    if (!coords) return null;
    return haversineKm(coords.lat, coords.lng, issue.latitude, issue.longitude);
  }

  const pendingVerify = history.filter(i => i.status === "PENDING_VERIFICATION");
  const meta = selected ? statusMeta(selected.status) : null;

  return (
    <MobileShell noPad splitView>
      {/* ── MAP: top 40% ── */}
      <div className="relative shrink-0" style={{ height: "40%" }}>
        <MapView
          center={center}
          issues={filteredMapIssues}
          radius={RADIUS}
          selectedId={selected?.id}
          onSelect={setSelected}
          boundaries={boundaries}
          currentWard={currentWard}
        />

        {/* Search bar */}
        <div className="absolute left-0 right-0 top-0 z-[400] px-3 pt-2">
          <div className="flex items-center gap-2 rounded-xl bg-white/95 px-3 py-2 shadow ring-1 ring-slate-200">
            <Search size={15} className="shrink-0 text-slate-400" />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search ticket no. or grievance nearby"
              className="min-w-0 flex-1 bg-transparent text-xs outline-none placeholder:text-slate-400"
            />
            {query && (
              <button onClick={() => setQuery("")} className="shrink-0 text-slate-400">
                <X size={14} />
              </button>
            )}
          </div>

          {query && (
            <div className="mt-1 max-h-40 overflow-y-auto rounded-xl bg-white/95 shadow ring-1 ring-slate-200">
              {filteredMapIssues.length === 0 ? (
                <p className="px-3 py-2.5 text-xs text-slate-400">No matching grievances nearby.</p>
              ) : (
                filteredMapIssues.map(i => {
                  const m = statusMeta(i.status);
                  return (
                    <button
                      key={i.id}
                      onClick={() => { setSelected(i); setQuery(""); }}
                      className="flex w-full items-center gap-2 border-b border-slate-100 px-3 py-2 text-left last:border-0 hover:bg-slate-50"
                    >
                      <span className="font-mono text-[10px] font-semibold text-slate-500">{ticketNumber(i.id)}</span>
                      <span className="min-w-0 flex-1 truncate text-xs font-medium text-slate-800">{i.title}</span>
                      <span className={`shrink-0 rounded-full px-1.5 py-0.5 text-[9px] font-semibold ${m.badge}`}>{m.label}</span>
                    </button>
                  );
                })
              )}
            </div>
          )}
        </div>

        {/* Real GCC zone/ward chip (hidden while searching) */}
        {!query && (
          <LocationDetector
            coords={coords}
            onResolved={setDetected}
            className="absolute right-3 top-14 z-[400]"
          />
        )}

        {/* Sneaky demo button: jump to an Egmore ward (our GPS is outside GCC). */}
        <button
          onClick={jumpToEgmore}
          title="Preview grievances in Egmore constituency"
          className={`absolute bottom-2 right-2 z-[500] flex h-7 w-7 items-center justify-center rounded-full border border-white/60 shadow-sm backdrop-blur transition-all duration-300 ${
            override ? "bg-brand text-white opacity-100" : "bg-white/50 text-slate-400 opacity-60 hover:bg-white hover:text-brand hover:opacity-100"
          }`}
        >
          <Landmark size={12} />
        </button>

        {/* Status legend */}
        <div className="absolute bottom-2 left-2 z-[400] flex flex-col gap-0.5 rounded-xl bg-white/90 p-1.5 text-[9px] shadow ring-1 ring-slate-200">
          {Object.entries(STATUS_META).filter(([k]) => k !== "SUBMITTED").map(([key, m]) => (
            <span key={key} className="flex items-center gap-1">
              <span className="inline-block h-2 w-2 rounded-full" style={{ background: m.pin }} />
              {m.label}
            </span>
          ))}
        </div>

        {selected && (
          <div className="absolute bottom-0 left-0 right-0 z-[450] rounded-t-2xl bg-white p-3 shadow-2xl">
            <div className="flex gap-3">
              {selected.image_url
                ? <img src={mediaUrl(selected.image_url)} alt="issue" className="h-16 w-16 rounded-xl object-cover" />
                : <div className="flex h-16 w-16 items-center justify-center rounded-xl bg-slate-100 text-2xl">🛣️</div>}
              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-1">
                  <p className="text-sm font-bold text-slate-900 leading-tight">{selected.title}</p>
                  <button onClick={() => setSelected(null)} className="text-slate-400 shrink-0">✕</button>
                </div>
                {selected.area_name && <p className="text-xs text-slate-500">{selected.area_name}</p>}
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <span className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold ${meta.badge}`}>
                    {meta.label}
                  </span>
                  {selected.ward_no != null && (
                    <span className="rounded-full bg-violet-50 px-2 py-0.5 text-[10px] font-semibold text-violet-700 ring-1 ring-violet-200">
                      Ward no: {selected.ward_no}
                    </span>
                  )}
                  <span className="font-mono text-[10px] font-semibold text-slate-400">{ticketNumber(selected.id)}</span>
                </div>
              </div>
            </div>
            {selected.summary_highlights?.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1">
                {selected.summary_highlights.map((h, i) => (
                  <span key={i} className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-medium text-brand">{h}</span>
                ))}
              </div>
            )}
            <div className="mt-2 flex items-center justify-between">
              <span className="flex items-center gap-1 text-sm font-semibold text-slate-700">
                <ThumbsUp size={13} /> {selected.upvotes}
                {selected.distance_m != null && (
                  <span className="ml-1 text-xs font-normal text-slate-400">{Math.round(selected.distance_m)} m</span>
                )}
              </span>
              <button
                onClick={() => setUpvoteTarget(selected)}
                className="flex items-center gap-1 rounded-xl bg-brand px-3 py-1.5 text-xs font-semibold text-white"
              >
                <ThumbsUp size={12} /> Upvote
              </button>
            </div>
          </div>
        )}
      </div>

      {/* ── BOTTOM 60%: tabs ── */}
      <div className="no-scrollbar flex-1 overflow-y-auto bg-slate-50 px-4 pt-3 pb-28">
        {/* Tab switcher */}
        <div className="mb-3 flex gap-1 rounded-xl bg-slate-200/70 p-1">
          <button
            onClick={() => setTab("ward")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${
              tab === "ward" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"
            }`}
          >
            <Users size={13} /> In My Ward{currentWard != null ? ` (${wardIssues.length})` : ""}
          </button>
          <button
            onClick={() => setTab("mine")}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${
              tab === "mine" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"
            }`}
          >
            <FileText size={13} /> My Reports ({history.length})
          </button>
        </div>

        {error && (
          <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{error}</p>
        )}

        {/* ── IN MY WARD ── */}
        {tab === "ward" && (
          <>
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-extrabold text-slate-900">
                Public grievances {currentWard != null ? `in Ward ${currentWard}` : "in your ward"}
              </h2>
              <button onClick={() => loadWard(currentWard)} className="flex items-center gap-1 text-xs font-medium text-brand">
                <RotateCcw size={12} /> Refresh
              </button>
            </div>
            {currentWard == null ? (
              <p className="py-8 text-center text-sm text-slate-400">Locating your ward…</p>
            ) : wardIssues.length === 0 ? (
              <div className="py-10 text-center text-sm text-slate-400">
                <Users size={32} className="mx-auto mb-2 text-slate-300" />
                No public grievances in Ward {currentWard} yet.
              </div>
            ) : (
              <div className="space-y-2">
                {wardIssues.map(issue => (
                  <IssueCard
                    key={issue.id}
                    issue={issue}
                    expanded={expandedId === issue.id}
                    onToggle={() => toggleExpand(issue.id)}
                    dist={distanceKm(issue)}
                    onUpvote={setUpvoteTarget}
                  />
                ))}
              </div>
            )}
          </>
        )}

        {/* ── MY REPORTS ── */}
        {tab === "mine" && (
          <>
            {pendingVerify.length > 0 && (
              <div className="mb-3 space-y-2">
                {pendingVerify.map(issue => (
                  <div key={issue.id} className="rounded-xl border border-amber-200 bg-amber-50 p-3">
                    <div className="flex items-center gap-2 mb-2">
                      <SlidersHorizontal size={14} className="text-amber-600" />
                      <p className="text-xs font-bold text-amber-800">Action Required — {issue.title}</p>
                    </div>
                    <p className="text-xs text-amber-700 mb-2">
                      Authority marked this issue as RESOLVED. Has it really been fixed?
                    </p>
                    <div className="flex gap-2">
                      <button
                        disabled={busyId === issue.id}
                        onClick={() => handleVerify(issue, "APPROVED")}
                        className="flex flex-1 items-center justify-center gap-1 rounded-lg bg-green-600 py-2 text-xs font-semibold text-white disabled:opacity-60"
                      >
                        <CheckCircle2 size={13} /> Approve & Close
                      </button>
                      <button
                        disabled={busyId === issue.id}
                        onClick={() => handleVerify(issue, "REJECTED")}
                        className="flex flex-1 items-center justify-center gap-1 rounded-lg border border-red-300 bg-white py-2 text-xs font-semibold text-red-600 disabled:opacity-60"
                      >
                        <XCircle size={13} /> Reject / Not Fixed
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-sm font-extrabold text-slate-900">My Grievances</h2>
              <button onClick={() => loadHistory(userId)} className="flex items-center gap-1 text-xs font-medium text-brand">
                <RotateCcw size={12} /> Refresh
              </button>
            </div>

            {histLoading ? (
              <p className="text-center text-sm text-slate-400 py-8">Loading…</p>
            ) : history.length === 0 ? (
              <div className="py-10 text-center text-sm text-slate-400">
                <MapPin size={32} className="mx-auto mb-2 text-slate-300" />
                No reports yet. Submit one from the Report tab.
              </div>
            ) : (
              <div className="space-y-2">
                {history.map(issue => (
                  <IssueCard
                    key={issue.id}
                    issue={issue}
                    expanded={expandedId === issue.id}
                    onToggle={() => toggleExpand(issue.id)}
                    dist={distanceKm(issue)}
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {upvoteTarget && (
        <UpvoteModal
          issue={upvoteTarget}
          onConfirm={confirmUpvote}
          onClose={() => setUpvoteTarget(null)}
        />
      )}
    </MobileShell>
  );
}
