"use client";

/**
 * Petition Review — the verification gate.
 * Grievances submitted by citizens land here as "Pending Verification". A staff
 * member reviews the photo/audio/details and clicks "Verify Grievance", which
 * flips SUBMITTED → ACTIVE on the backend (exactly the existing flow) — the
 * grievance then goes public in the citizen app and enters the Tickets queue.
 */

import { useEffect, useMemo, useState } from "react";
import {
  ClipboardCheck, ShieldCheck, ImageIcon, Volume2, MapPin, Phone,
  ThumbsUp, Search, X, Landmark, ArrowRightLeft, CheckCircle2, Ban, Send,
  Sparkles, MessageSquare,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import TicketDrawer from "@/components/admin/TicketDrawer";
import { adminVerifyGrievance } from "@/lib/api";
import { citizenName, initials, tokenNo, daysOpen } from "@/lib/adminModel";
import { constituenciesForWard, shortAC } from "@/lib/constituencies";
import { listCoordinatorsRemote } from "@/lib/coordinators";
import { ACTION_KINDS } from "@/lib/coordinatorActions";
import { departmentMeta } from "@/lib/departments";

// Which real backend status(es) back each coordinator-action tab. The action
// tabs used to read a coordinator-app localStorage bag; they now derive from the
// grievance's live status + coordinator_message, so mobile-coordinator actions
// show up too (the localStorage bag was web-coordinator only).
function matchesActionTab(issue, tab) {
  switch (tab) {
    case "redirect": // coordinator bounced it back to the citizen (SUBMITTED + apology msg)
      return issue.status === "SUBMITTED" && !!issue.coordinator_message;
    case "transfer": // routed to a department
      return issue.status === "FORWARDED";
    case "close":    // coordinator marked resolved (awaiting citizen verify, or verified)
      return (issue.status === "PENDING_VERIFICATION" || issue.status === "CLOSED")
        && !!issue.assigned_coordinator;
    case "false":    // marked a false petition
      return issue.status === "FALSE";
    default:
      return false;
  }
}

const AVATAR_TINTS = ["bg-blue-100 text-blue-700", "bg-emerald-100 text-emerald-700",
  "bg-violet-100 text-violet-700", "bg-amber-100 text-amber-700", "bg-rose-100 text-rose-700"];
function tint(seed) {
  let h = 0; for (const c of seed || "x") h = (h * 31 + c.charCodeAt(0)) % AVATAR_TINTS.length;
  return AVATAR_TINTS[h];
}

const TABS = [
  { key: "pending",  label: "Pending Verification", icon: ClipboardCheck },
  { key: "redirect", label: "Redirected",           icon: ArrowRightLeft },
  { key: "transfer", label: "Transferred",          icon: Send },
  { key: "close",    label: "Closed by Coordinator", icon: CheckCircle2 },
  { key: "false",    label: "False Petitions",      icon: Ban },
];

export default function PetitionReviewPage() {
  const { pending, issues, loading, reload } = useAdminData();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [tab, setTab] = useState("pending");
  const [coordMap, setCoordMap] = useState({});

  // Resolve coordinator usernames → their profile (name/role/constituency) so
  // action rows can name who actioned each grievance. Backend-backed directory.
  useEffect(() => {
    let alive = true;
    listCoordinatorsRemote()
      .then((list) => {
        if (alive) setCoordMap(Object.fromEntries(list.map((c) => [c.username, c])));
      })
      .catch(() => {});
    return () => { alive = false; };
  }, []);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return pending;
    return pending.filter((i) =>
      [citizenName(i), i.phone, i.title, tokenNo(i)].some((v) => (v || "").toString().toLowerCase().includes(q)));
  }, [pending, query]);

  const actionRows = useMemo(() => {
    if (tab === "pending") return [];
    const q = query.trim().toLowerCase();
    return (issues || [])
      .filter((i) => matchesActionTab(i, tab))
      .filter((i) => !q || [citizenName(i), i.phone, i.title, tokenNo(i), i.assigned_coordinator]
        .some((v) => (v || "").toString().toLowerCase().includes(q)))
      .sort((a, b) => (b.escalated_at || b.created_at || "").localeCompare(a.escalated_at || a.created_at || ""));
  }, [issues, tab, query]);

  const counts = useMemo(() => {
    const c = { pending: pending.length, redirect: 0, transfer: 0, close: 0, false: 0 };
    for (const i of issues || []) {
      for (const k of ["redirect", "transfer", "close", "false"]) {
        if (matchesActionTab(i, k)) c[k]++;
      }
    }
    return c;
  }, [pending.length, issues]);

  async function verify(id, e) {
    e?.stopPropagation();
    setBusyId(id);
    try { await adminVerifyGrievance(id); await reload(); }
    finally { setBusyId(null); }
  }

  return (
    <>
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-violet-600"><ClipboardCheck size={20} /></div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Petition Review</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Verify citizen grievances before they go live</p>
          </div>
        </div>
        <span className="rounded-full bg-violet-100 px-3 py-1 text-xs font-bold text-violet-700">{pending.length} pending</span>
      </header>

      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-hidden px-7 py-5">
        <div className="glass-panel flex items-center gap-2.5 rounded-2xl px-4 py-3">
          <Search size={18} className="text-slate-400" />
          <input value={query} onChange={(e) => setQuery(e.target.value)}
            placeholder={tab === "pending" ? "Search pending petitions…" : "Search actioned petitions…"}
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400" />
          {query && <button onClick={() => setQuery("")}><X size={16} className="text-slate-400" /></button>}
        </div>

        {/* Tabs */}
        <div className="glass-panel flex flex-wrap items-center gap-1 rounded-2xl px-2 py-1.5">
          {TABS.map((t) => (
            <button key={t.key} onClick={() => setTab(t.key)}
              className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition ${
                tab === t.key ? "bg-brand text-white" : "text-slate-600 hover:bg-slate-100"
              }`}>
              <t.icon size={13} /> {t.label}
              <span className={`ml-1 rounded-full px-1.5 text-[10px] font-bold ${
                tab === t.key ? "bg-white/20 text-white" : "bg-slate-100 text-slate-500"
              }`}>{counts[t.key]}</span>
            </button>
          ))}
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {tab !== "pending" ? (
            <ActionsList kind={tab} issues={actionRows} coordMap={coordMap} />
          ) : loading ? (
            <p className="py-16 text-center text-slate-400">Loading…</p>
          ) : rows.length === 0 ? (
            <div className="py-24 text-center text-slate-400">
              <ShieldCheck size={40} className="mx-auto mb-3 text-emerald-300" />
              <p className="font-semibold">All caught up — no petitions pending verification.</p>
            </div>
          ) : (
            /* Single-column list, matching the Tickets table: sticky header,
               hairline row separators, hover highlight, no zebra striping. */
            <div className="glass-panel-strong overflow-auto rounded-2xl">
              <table className="w-full border-collapse text-sm">
                <thead className="sticky top-0 z-10 bg-white/70 text-left text-[11px] font-bold uppercase tracking-wider text-slate-400 backdrop-blur">
                  <tr>
                    <th className="px-5 py-3">Status</th>
                    <th className="px-3 py-3">Citizen</th>
                    <th className="px-3 py-3">Description</th>
                    <th className="px-3 py-3">Attachments</th>
                    <th className="px-3 py-3">Location</th>
                    <th className="px-3 py-3">Upvotes</th>
                    <th className="px-3 py-3 text-right">Date</th>
                    <th className="px-3 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((issue) => {
                    const name = citizenName(issue);
                    const acs = constituenciesForWard(issue.ward_no);
                    return (
                      <tr key={issue.id} onClick={() => setSelected(issue)}
                        style={{ transition: "background .25s ease" }}
                        className="group cursor-pointer border-t border-slate-200/50 hover:bg-white/60">
                        {/* Status */}
                        <td className="px-5 py-3.5">
                          <span className="flex items-center gap-1.5 whitespace-nowrap">
                            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-violet-500 glow-pending" />
                            <span className="text-[11px] font-bold uppercase tracking-wide text-violet-700">Pending</span>
                          </span>
                        </td>
                        {/* Citizen */}
                        <td className="px-3 py-3.5">
                          <div className="flex items-center gap-2.5">
                            <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold ${tint(name)}`}>{initials(name)}</span>
                            <div className="min-w-0">
                              <p className="truncate font-bold text-slate-800">{name}</p>
                              <p className="flex items-center gap-1 text-[11px] text-slate-400"><Phone size={10} /> {issue.phone ? `+91 ${issue.phone}` : "—"}</p>
                            </div>
                          </div>
                        </td>
                        {/* Description — takes the leftover width, single line.
                            w-full claims the slack; max-w-0 lets truncate work. */}
                        <td className="w-full max-w-0 px-3 py-3.5">
                          <p className="truncate text-slate-700">
                            {issue.title || <span className="italic text-slate-400">No headline</span>}
                          </p>
                        </td>
                        {/* Attachments */}
                        <td className="px-3 py-3.5">
                          <div className="flex items-center gap-1.5 text-[11px]">
                            {issue.image_url && <Chip icon={ImageIcon}>Photo</Chip>}
                            {issue.audio_url && <Chip icon={Volume2}>Audio</Chip>}
                            {!issue.image_url && !issue.audio_url && <span className="text-slate-300">—</span>}
                          </div>
                        </td>
                        {/* Location */}
                        <td className="px-3 py-3.5">
                          <div className="flex items-center gap-1.5 text-[11px]">
                            {issue.ward_no != null && <Chip icon={MapPin}>Ward {issue.ward_no}</Chip>}
                            {acs.length > 0 && <Chip icon={Landmark}>{shortAC(acs[0])}</Chip>}
                            {issue.ward_no == null && acs.length === 0 && <span className="text-slate-300">—</span>}
                          </div>
                        </td>
                        {/* Upvotes */}
                        <td className="px-3 py-3.5">
                          <span className="flex items-center gap-1 text-[11px] font-semibold text-slate-500">
                            <ThumbsUp size={11} /> {issue.upvotes || 0}
                          </span>
                        </td>
                        {/* Time ago */}
                        <td className="whitespace-nowrap px-3 py-3.5 text-right text-[11px] text-slate-400">
                          {daysOpen(issue)}d ago
                        </td>
                        {/* Action */}
                        <td className="px-3 py-3.5 text-right">
                          <button
                            onClick={(e) => verify(issue.id, e)}
                            disabled={busyId === issue.id}
                            className="inline-flex h-8 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg bg-violet-600 px-3 text-xs font-bold text-white transition hover:bg-violet-700 disabled:opacity-60"
                          >
                            <ShieldCheck size={13} /> {busyId === issue.id ? "Verifying…" : "Verify"}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {selected && (
        <TicketDrawer
          issue={selected}
          onClose={() => setSelected(null)}
          onChanged={async () => { await reload(); setSelected(null); }}
        />
      )}
    </>
  );
}

function Chip({ icon: Icon, children }) {
  return (
    <span className="flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 font-semibold text-slate-500">
      <Icon size={11} /> {children}
    </span>
  );
}

/* ── Coordinator-actioned petitions list (derived from live grievance status) ── */
function ActionsList({ kind, issues, coordMap }) {
  const meta = ACTION_KINDS[kind];

  if (!issues.length) {
    return (
      <div className="py-24 text-center text-slate-400">
        <ClipboardCheck size={40} className="mx-auto mb-3 text-slate-300" />
        <p className="font-semibold">No petitions in the {meta?.label || "this"} bucket yet.</p>
        <p className="text-xs">Grievances appear here as coordinators action them in the app.</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {issues.map((issue) => {
        const uname = issue.assigned_coordinator;
        const coord = uname ? coordMap[uname] : null;
        const when = issue.escalated_at || issue.rejected_at || issue.created_at;
        return (
          <article key={issue.id} className="glass-panel rounded-2xl p-4">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="text-sm font-bold text-slate-800">{issue.title || "Grievance"}</p>
                <p className="mt-0.5 flex flex-wrap items-center gap-2 text-[11px] text-slate-500">
                  {issue.ward_no != null && <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold">Ward {issue.ward_no}</span>}
                  {issue.department && <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold">{departmentMeta(issue.department).short}</span>}
                  {issue.constituency && <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold">{shortAC(issue.constituency)}</span>}
                  <span className="rounded bg-slate-100 px-1.5 py-0.5 font-mono">{issue.ticket_number || `#${(issue.id || "").slice(0, 8)}`}</span>
                </p>
              </div>
              <span className={`rounded-full px-2.5 py-1 text-[10px] font-bold ring-1 ${meta.tone}`}>{meta.label}</span>
            </div>

            {/* Who actioned it */}
            {uname && (
              <div className="mt-3 flex items-center gap-2 rounded-lg bg-slate-50 px-2.5 py-1.5">
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-brand/10 text-[10px] font-bold text-brand">
                  {initials(coord?.name || uname)}
                </span>
                <p className="text-[11px] text-slate-500">
                  Actioned by <span className="font-semibold text-slate-800">{coord?.name || `@${uname}`}</span>
                  {coord?.constituency && <span className="text-slate-400"> · {shortAC(coord.constituency)}</span>}
                  {when && <span className="text-slate-400"> · {new Date(when).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })}</span>}
                </p>
              </div>
            )}

            {/* Kind-specific payload (from the grievance's own fields) */}
            <ActionPayload kind={kind} issue={issue} />
          </article>
        );
      })}
    </div>
  );
}

function ActionPayload({ kind, issue }) {
  const msg = issue.coordinator_message;
  if (kind === "transfer") {
    return (
      <div className="mt-3 space-y-2">
        <div className="rounded-xl border border-brand-100 bg-brand-50/60 p-3">
          <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-brand">
            <Sparkles size={11} /> Routed to
          </p>
          <p className="text-sm font-bold text-slate-800">{issue.department || "Department (unspecified)"}</p>
        </div>
        {msg && (
          <div className="rounded-xl border border-slate-200 bg-white p-3">
            <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-slate-500">Coordinator note</p>
            <p className="text-[13px] italic leading-snug text-slate-700">"{msg}"</p>
          </div>
        )}
      </div>
    );
  }
  if (kind === "false") {
    return (
      <div className="mt-3 rounded-xl border border-rose-100 bg-rose-50/50 p-3">
        <p className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-rose-600">
          <Ban size={11} /> Marked false
        </p>
        <p className="text-[13px] italic leading-snug text-slate-700">{msg ? `"${msg}"` : "No reason recorded."}</p>
      </div>
    );
  }
  // redirect + close: surface the coordinator's citizen-facing message.
  if (!msg) return null;
  const isRedirect = kind === "redirect";
  return (
    <div className={`mt-3 rounded-xl border p-3 ${isRedirect ? "border-slate-200 bg-white" : "border-emerald-100 bg-emerald-50/50"}`}>
      <p className={`mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide ${isRedirect ? "text-slate-500" : "text-emerald-600"}`}>
        {isRedirect ? <MessageSquare size={11} /> : <CheckCircle2 size={11} />} {isRedirect ? "Redirect message" : "Resolution note"}
      </p>
      <p className="text-[13px] italic leading-snug text-slate-700">"{msg}"</p>
    </div>
  );
}
