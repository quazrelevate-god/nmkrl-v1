"use client";

/**
 * CitizenProfileHeader
 * --------------------
 * Phase-1 home (map) header. Holds the two pieces relocated from the retired
 * Community screen:
 *   1. the brand bar + citizen avatar (tap → expand/collapse the profile), and
 *   2. the "Constituency highlights" bar (heading + AC selector + stories).
 *
 * Unlike the old drag-morph community header, the profile here is a simple
 * tap-to-toggle panel that pushes content down — keeping the home spacious and
 * uncluttered, with each block clearly separated.
 */

import { useRouter } from "next/navigation";
import {
  ChevronDown, ChevronUp, ShieldCheck, Flame, ClipboardList, ThumbsUp,
  CheckCircle2, Trophy, Star, MapPin, LogOut,
} from "lucide-react";
import { PROFILE, STORIES } from "@/lib/communityData";
import { CONSTITUENCIES, shortAC } from "@/lib/constituencies";

function greetingFor(h) {
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

/* ── Brand wordmark: நம்குரல் in deep navy with the gold signal-wave mark. ── */
function BrandMark() {
  const ink = "#1a3556";
  return (
    <div className="relative inline-flex select-none items-end leading-none">
      <span className="text-[22px] font-black tracking-tight" style={{ color: ink }}>நம்குரல்</span>
      <svg viewBox="0 0 40 40" className="absolute -top-2.5 left-[38px] h-4 w-4" style={{ color: "#c8a04a" }} aria-hidden>
        <circle cx="10" cy="30" r="3" fill="currentColor" />
        <path d="M10 21 A15 15 0 0 1 28 37" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
        <path d="M10 14 A22 22 0 0 1 34 37" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </svg>
    </div>
  );
}

/* ── The expandable citizen profile: civic score, stats, impact, sign out. ── */
function ProfilePanel({ onCollapse }) {
  const router = useRouter();
  const greeting = greetingFor(new Date().getHours());
  const pctInTier = Math.round(((PROFILE.levelSpan - PROFILE.toNext) / PROFILE.levelSpan) * 100);

  function logout() {
    try { localStorage.removeItem("nk_citizen_authed"); } catch { /* ignore */ }
    router.replace("/login");
  }

  const stats = [
    { icon: ClipboardList, value: PROFILE.reports,  label: "Reports",  tint: "text-brand bg-brand-50" },
    { icon: ThumbsUp,      value: PROFILE.upvotes,  label: "Upvotes",  tint: "text-teal-700 bg-teal-50" },
    { icon: CheckCircle2,  value: PROFILE.resolved, label: "Resolved", tint: "text-emerald-700 bg-emerald-50" },
    { icon: Trophy,        value: PROFILE.rank,     label: "Rank",     tint: "text-slate-600 bg-slate-100" },
  ];

  return (
    <div className="px-4 pb-4">
      {/* Hero */}
      <div className="flex items-center gap-3">
        <div className="relative shrink-0">
          <div className="rounded-full bg-gradient-to-br from-amber-300 via-yellow-400 to-amber-500 p-[3px]">
            <div className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-white bg-slate-100 text-xl font-black text-brand">
              {PROFILE.name.split(" ").map(w => w[0]).join("")}
            </div>
          </div>
          <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-md bg-gradient-to-r from-amber-300 to-yellow-500 px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide text-brand-dark shadow">{PROFILE.level}</span>
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-medium text-slate-400">{greeting},</p>
          <h2 className="truncate text-lg font-extrabold leading-tight text-slate-900">{PROFILE.name} 👋</h2>
          <span className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-bold text-brand">
            <Flame size={10} className="fill-brand text-brand" /> {PROFILE.streak}-day streak
          </span>
        </div>
        <button onClick={onCollapse} className="self-start rounded-full p-1 text-slate-400 hover:bg-slate-200/60">
          <ChevronUp size={18} />
        </button>
      </div>

      {/* Civic score — royal-green card with a "golden ticket" tier badge */}
      <div className="mt-3 overflow-hidden rounded-2xl bg-gradient-to-br from-brand via-brand-700 to-brand-dark p-3.5 text-white shadow-lg shadow-brand/25">
        <div className="flex items-end justify-between">
          <div>
            <p className="flex items-center gap-1 text-[11px] font-semibold text-emerald-100"><ShieldCheck size={13} /> Civic Score</p>
            <div className="flex items-center gap-2">
              <p className="text-3xl font-black leading-none">{PROFILE.civicScore}</p>
              <span className="relative inline-flex items-center rounded-md bg-gradient-to-r from-amber-300 via-yellow-400 to-amber-500 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-brand-dark shadow-[inset_0_1px_0_rgba(255,255,255,0.4),0_2px_6px_rgba(217,119,6,0.4)]">
                <span className="pointer-events-none absolute -left-1 top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-brand" />
                <span className="pointer-events-none absolute -right-1 top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-brand" />
                {PROFILE.level}
              </span>
            </div>
          </div>
          <div className="text-right">
            <div className="flex justify-end gap-0.5">
              {Array.from({ length: 5 }).map((_, i) => (
                <Star key={i} size={12} className={i < Math.round(PROFILE.rating) ? "fill-amber-300 text-amber-300" : "fill-white/25 text-white/25"} />
              ))}
            </div>
            <p className="mt-0.5 text-[10px] text-emerald-100">{PROFILE.rating}/5 rating</p>
          </div>
        </div>
        <div className="mt-2.5">
          <div className="mb-1 flex items-center justify-between text-[10px] font-medium text-emerald-100">
            <span>{PROFILE.level}</span>
            <span>{PROFILE.toNext} pts to {PROFILE.nextLevel}</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-white/20">
            <div className="h-full rounded-full bg-gradient-to-r from-amber-300 to-yellow-200" style={{ width: `${pctInTier}%` }} />
          </div>
        </div>
      </div>

      {/* Stat tiles */}
      <div className="mt-3 grid grid-cols-4 gap-2">
        {stats.map(({ icon: Icon, value, label, tint }) => (
          <div key={label} className="rounded-2xl bg-white p-2 text-center ring-1 ring-slate-200/70 shadow-sm">
            <span className={`mx-auto flex h-7 w-7 items-center justify-center rounded-full ${tint}`}><Icon size={15} /></span>
            <p className="mt-1 text-sm font-extrabold leading-none text-slate-800">{value}</p>
            <p className="text-[9px] font-medium text-slate-500">{label}</p>
          </div>
        ))}
      </div>

      {/* Impact banner */}
      <div className="mt-3 flex items-center gap-3 rounded-2xl bg-gradient-to-br from-emerald-50 to-teal-50 px-4 py-3.5 ring-1 ring-emerald-100">
        <span className="text-2xl">🙌</span>
        <div>
          <p className="text-sm font-bold leading-snug text-emerald-900">
            You've improved <span className="text-emerald-700">{PROFILE.streets}+ streets &amp; public spaces</span>.
          </p>
          <p className="mt-0.5 text-xs leading-snug text-emerald-700">
            Thank you for building a better Tamil Nadu. <span className="font-semibold">— Hon'ble CM</span>
          </p>
        </div>
      </div>

      {/* Sign out */}
      <button
        onClick={logout}
        className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-2xl border border-slate-200 bg-white py-2.5 text-xs font-bold text-slate-600 hover:bg-slate-50"
      >
        <LogOut size={13} /> Sign out
      </button>
    </div>
  );
}

/* ── Constituency highlights bar: heading + AC selector + stories strip. ── */
function ConstituencyHighlights({ onOpenStory, constituency, onConstituency }) {
  return (
    <div className="px-4 pb-1">
      <div className="mb-2.5 flex items-center justify-between gap-2">
        <h2 className="text-[17px] font-extrabold tracking-tight text-slate-900">Constituency highlights</h2>
        <div className="inline-flex shrink-0 items-center gap-1 rounded-full bg-white py-1.5 pl-2.5 pr-1.5 ring-1 ring-slate-200 shadow-sm">
          <MapPin size={12} className="shrink-0 text-brand" />
          <div className="relative flex items-center">
            <select
              value={constituency}
              onChange={(e) => onConstituency(e.target.value)}
              className="max-w-[130px] cursor-pointer appearance-none truncate bg-transparent pr-4 text-[12px] font-bold text-slate-700 outline-none"
            >
              {CONSTITUENCIES.map((c) => (
                <option key={c} value={c}>{shortAC(c)}</option>
              ))}
            </select>
            <ChevronDown size={12} className="pointer-events-none absolute right-0 text-slate-400" />
          </div>
        </div>
      </div>
      <div className="no-scrollbar -mx-1 flex gap-3.5 overflow-x-auto px-1 pb-1">
        {STORIES.map(s => (
          <button key={s.id} onClick={() => onOpenStory(s)} className="flex w-[72px] shrink-0 flex-col items-center gap-1.5">
            <span className="relative rounded-[22px] bg-gradient-to-br from-gold-200 via-gold-300 to-gold-400 p-[2.5px] shadow-sm">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s.slides[0].image} alt="" className="h-[66px] w-[66px] rounded-[20px] border-2 border-white object-cover" />
              {s.count > 0 && (
                <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-brand px-1 text-[10px] font-bold text-white ring-2 ring-white">{s.count}</span>
              )}
            </span>
            <span className="line-clamp-2 text-center text-[10px] font-semibold leading-tight text-slate-600">{s.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

export default function CitizenProfileHeader({
  profileOpen, onToggleProfile, onOpenStory, constituency, onConstituencyChange,
}) {
  const initials = PROFILE.name.split(" ").map((w) => w[0]).join("").slice(0, 2);

  return (
    <header className="glass-clear relative z-30 rounded-b-[28px] shadow-[0_16px_36px_-22px_rgba(15,23,42,0.25)]">
      {/* Faux status bar (matches the rest of the app) */}
      <div className="flex items-center justify-between px-5 pt-2.5 pb-1 text-[12px] font-semibold text-slate-800">
        <span>9:41</span>
        <span className="flex items-center gap-1.5">
          <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
          <span className="tracking-tighter">5G</span>
          <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
        </span>
      </div>

      {/* Brand bar + avatar (avatar toggles the profile) */}
      <div className="flex items-center justify-between px-4 pb-2.5 pt-0.5">
        <BrandMark />
        <button
          onClick={onToggleProfile}
          aria-label={profileOpen ? "Close profile" : "Open profile"}
          className="relative"
        >
          <span className="block rounded-full bg-gradient-to-br from-amber-300 via-yellow-400 to-amber-500 p-[2px] shadow-sm">
            <span className="flex h-9 w-9 items-center justify-center rounded-full border-2 border-white bg-slate-100 text-[13px] font-black text-brand">
              {initials}
            </span>
          </span>
          <span className="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-white bg-emerald-500" />
        </button>
      </div>

      {/* Profile panel — expands on avatar tap */}
      {profileOpen && <ProfilePanel onCollapse={onToggleProfile} />}

      {/* Constituency highlights bar */}
      <ConstituencyHighlights
        onOpenStory={onOpenStory}
        constituency={constituency}
        onConstituency={onConstituencyChange}
      />
    </header>
  );
}
