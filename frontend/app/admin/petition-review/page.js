"use client";

/**
 * Petition Review — the verification gate.
 * Grievances submitted by citizens land here as "Pending Verification". A staff
 * member reviews the photo/audio/details and clicks "Verify Grievance", which
 * flips SUBMITTED → ACTIVE on the backend (exactly the existing flow) — the
 * grievance then goes public in the citizen app and enters the Tickets queue.
 */

import { useMemo, useState } from "react";
import {
  ClipboardCheck, ShieldCheck, ImageIcon, Volume2, MapPin, Phone,
  ThumbsUp, Search, X, Landmark,
} from "lucide-react";
import { useAdminData } from "@/components/admin/AdminDataProvider";
import TicketDrawer from "@/components/admin/TicketDrawer";
import { adminVerifyGrievance } from "@/lib/api";
import { citizenName, initials, tokenNo, daysOpen } from "@/lib/adminModel";
import { constituenciesForWard, shortAC } from "@/lib/constituencies";

const AVATAR_TINTS = ["bg-blue-100 text-blue-700", "bg-emerald-100 text-emerald-700",
  "bg-violet-100 text-violet-700", "bg-amber-100 text-amber-700", "bg-rose-100 text-rose-700"];
function tint(seed) {
  let h = 0; for (const c of seed || "x") h = (h * 31 + c.charCodeAt(0)) % AVATAR_TINTS.length;
  return AVATAR_TINTS[h];
}

export default function PetitionReviewPage() {
  const { pending, loading, reload } = useAdminData();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return pending;
    return pending.filter((i) =>
      [citizenName(i), i.phone, i.title, tokenNo(i)].some((v) => (v || "").toString().toLowerCase().includes(q)));
  }, [pending, query]);

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
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search pending petitions…"
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400" />
          {query && <button onClick={() => setQuery("")}><X size={16} className="text-slate-400" /></button>}
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {loading ? (
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
