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
  Sparkles, User, MessageSquare, Camera, Mic, Clock,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import TicketDrawer from "@/components/admin/TicketDrawer";
import { adminVerifyGrievance } from "@/lib/api";
import { citizenName, initials, tokenNo, daysOpen } from "@/lib/adminModel";
import { constituenciesForWard, shortAC } from "@/lib/constituencies";
import { COORDINATORS } from "@/lib/coordinators";
import { loadCoordinatorActions, ACTION_KINDS } from "@/lib/coordinatorActions";
import { departmentMeta } from "@/lib/departments";

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
  const { pending, loading, reload } = useAdminData();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [tab, setTab] = useState("pending");
  const [coordActions, setCoordActions] = useState([]);

  // Load coordinator actions from localStorage (writable by CoordinatorProvider
  // in a separate app; polled here so newly-submitted actions surface without
  // requiring a hard reload).
  useEffect(() => {
    const load = () => setCoordActions(loadCoordinatorActions());
    load();
    const t = setInterval(load, 2500);
    const onStorage = () => load();
    window.addEventListener("storage", onStorage);
    return () => { clearInterval(t); window.removeEventListener("storage", onStorage); };
  }, []);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return pending;
    return pending.filter((i) =>
      [citizenName(i), i.phone, i.title, tokenNo(i)].some((v) => (v || "").toString().toLowerCase().includes(q)));
  }, [pending, query]);

  const actionRows = useMemo(() => {
    const kindMap = { redirect: "redirect", transfer: "transfer", close: "close", false: "false" };
    return coordActions.filter((a) => a.kind === kindMap[tab]);
  }, [coordActions, tab]);

  const counts = useMemo(() => {
    const c = { pending: pending.length, redirect: 0, transfer: 0, close: 0, false: 0 };
    for (const a of coordActions) { if (c[a.kind] != null) c[a.kind]++; }
    return c;
  }, [pending.length, coordActions]);

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
            <ActionsList kind={tab} actions={actionRows} />
          ) : loading ? (
            <p className="py-16 text-center text-slate-400">Loading…</p>
          ) : rows.length === 0 ? (
            <div className="py-24 text-center text-slate-400">
              <ShieldCheck size={40} className="mx-auto mb-3 text-emerald-300" />
              <p className="font-semibold">All caught up — no petitions pending verification.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              {rows.map((issue) => {
                const name = citizenName(issue);
                const acs = constituenciesForWard(issue.ward_no);
                return (
                  <article key={issue.id} onClick={() => setSelected(issue)}
                    className="glass-panel glass-hover group cursor-pointer overflow-hidden rounded-2xl">
                    <div className="flex items-center gap-1.5 border-b border-violet-200/50 bg-violet-50/60 px-4 py-2">
                      <span className="h-1.5 w-1.5 rounded-full bg-violet-500 glow-pending" />
                      <span className="text-[11px] font-bold uppercase tracking-wide text-violet-700">Pending Verification</span>
                      <span className="ml-auto text-[11px] text-violet-400">{daysOpen(issue)}d ago</span>
                    </div>

                    <div className="p-4">
                      <div className="flex items-center gap-2.5">
                        <span className={`flex h-9 w-9 items-center justify-center rounded-full text-xs font-bold ${tint(name)}`}>{initials(name)}</span>
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-bold text-slate-800">{name}</p>
                          <p className="flex items-center gap-1 text-[11px] text-slate-400"><Phone size={10} /> {issue.phone ? `+91 ${issue.phone}` : "—"}</p>
                        </div>
                      </div>

                      <p className="mt-3 line-clamp-2 min-h-[2.5rem] text-sm text-slate-700">
                        {issue.title || <span className="italic text-slate-400">No headline</span>}
                      </p>

                      <div className="mt-3 flex flex-wrap items-center gap-1.5 text-[11px]">
                        {issue.image_url && <Chip icon={ImageIcon}>Photo</Chip>}
                        {issue.audio_url && <Chip icon={Volume2}>Audio</Chip>}
                        {issue.ward_no != null && <Chip icon={MapPin}>Ward {issue.ward_no}</Chip>}
                        {acs.length > 0 && <Chip icon={Landmark}>{shortAC(acs[0])}</Chip>}
                        {issue.upvotes > 0 && <Chip icon={ThumbsUp}>{issue.upvotes}</Chip>}
                      </div>

                      <button
                        onClick={(e) => verify(issue.id, e)}
                        disabled={busyId === issue.id}
                        className="mt-4 flex w-full items-center justify-center gap-1.5 rounded-xl bg-violet-600 py-2.5 text-sm font-bold text-white transition hover:bg-violet-700 disabled:opacity-60"
                      >
                        <ShieldCheck size={15} /> {busyId === issue.id ? "Verifying…" : "Verify Grievance"}
                      </button>
                    </div>
                  </article>
                );
              })}
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

/* ── Coordinator-actioned petitions list ── */
function ActionsList({ kind, actions }) {
  const coordinatorMap = Object.fromEntries(COORDINATORS.map((c) => [c.username, c]));
  const meta = ACTION_KINDS[kind];

  if (!actions.length) {
    return (
      <div className="py-24 text-center text-slate-400">
        <ClipboardCheck size={40} className="mx-auto mb-3 text-slate-300" />
        <p className="font-semibold">No petitions in the {meta?.label || "this"} bucket yet.</p>
        <p className="text-xs">Coordinator actions surface here once they submit them.</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {actions.map((a) => {
        const coord = coordinatorMap[a.coordinator];
        return (
          <article key={a.id} className="glass-panel rounded-2xl p-4">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="text-sm font-bold text-slate-800">{a.issueTitle || "Grievance"}</p>
                <p className="mt-0.5 flex items-center gap-2 text-[11px] text-slate-500">
                  {a.wardNo != null && <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold">Ward {a.wardNo}</span>}
                  {a.department && <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold">{departmentMeta(a.department).short}</span>}
                  <span className="rounded bg-slate-100 px-1.5 py-0.5 font-mono">#{(a.issueId || "").slice(0, 8)}</span>
                </p>
              </div>
              <span className={`rounded-full px-2.5 py-1 text-[10px] font-bold ring-1 ${meta.tone}`}>{meta.label}</span>
            </div>

            {/* Coordinator info */}
            {coord && (
              <div className="mt-3 flex items-center gap-2 rounded-lg bg-slate-50 px-2.5 py-1.5">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={coord.avatar} alt="" className="h-6 w-6 rounded-full object-cover" />
                <p className="text-[11px] text-slate-500">
                  Actioned by <span className="font-semibold text-slate-800">{coord.name}</span>
                  <span className="text-slate-400"> · {shortAC(coord.constituency)}</span>
                  <span className="text-slate-400"> · {new Date(a.timestamp).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })}</span>
                </p>
              </div>
            )}

            {/* Kind-specific payload */}
            <ActionPayload kind={kind} data={a.data || {}} />
          </article>
        );
      })}
    </div>
  );
}

function ActionPayload({ kind, data }) {
  if (kind === "redirect") {
    return (
      <div className="mt-3 rounded-xl border border-slate-200 bg-white p-3">
        <p className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-500">
          <MessageSquare size={11} /> Reason for redirect
        </p>
        <p className="text-[13px] italic leading-snug text-slate-700">"{data.description}"</p>
      </div>
    );
  }
  if (kind === "transfer") {
    return (
      <div className="mt-3 space-y-2">
        <div className="rounded-xl border border-brand-100 bg-brand-50/60 p-3">
          <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-brand">
            <Sparkles size={11} /> Routed to
          </p>
          <p className="text-sm font-bold text-slate-800">{data.department}</p>
          {data.overridden && (
            <p className="text-[10px] text-amber-700">Coordinator overrode AI suggestion ({data.aiSuggested})</p>
          )}
        </div>
        {data.notes && (
          <div className="rounded-xl border border-slate-200 bg-white p-3">
            <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-slate-500">Notes</p>
            <p className="text-[13px] italic leading-snug text-slate-700">"{data.notes}"</p>
          </div>
        )}
      </div>
    );
  }
  if (kind === "close") {
    return (
      <div className="mt-3 grid grid-cols-2 gap-2">
        {data.photoUrl && (
          <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            <p className="flex items-center gap-1.5 px-2.5 pt-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-500">
              <Camera size={11} /> Closure photo
            </p>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={data.photoUrl} alt="" className="mt-1 h-28 w-full object-cover" />
          </div>
        )}
        {data.audioUrl && (
          <div className="rounded-xl border border-slate-200 bg-white p-2.5">
            <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-500">
              <Mic size={11} /> Voice note
            </p>
            <audio src={data.audioUrl} controls className="mt-1 h-8 w-full" />
            <p className="mt-1 flex items-center gap-1 text-[10px] text-slate-400"><Clock size={10} /> {data.audioSeconds}s</p>
          </div>
        )}
        {data.notes && (
          <div className="col-span-2 rounded-xl border border-slate-200 bg-white p-3">
            <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-slate-500">Notes</p>
            <p className="text-[13px] italic leading-snug text-slate-700">"{data.notes}"</p>
          </div>
        )}
      </div>
    );
  }
  if (kind === "false") {
    return (
      <div className="mt-3 rounded-xl border border-rose-100 bg-rose-50/50 p-3">
        <p className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-rose-600">
          <Ban size={11} /> Marked false — reason
        </p>
        <p className="text-sm font-semibold text-slate-800">{data.reason}</p>
        {data.details && <p className="mt-1 text-[13px] italic leading-snug text-slate-700">"{data.details}"</p>}
      </div>
    );
  }
  return null;
}
