"use client";

/**
 * CoordinatorHeader
 * -----------------
 * Adapted CommunityHeader for the /coordinator app. Same behaviour: fixed glass
 * top bar with a stories strip that morphs into the coordinator's own profile
 * on pull-down. Two coordinator-specific changes:
 *   • the profile shows the signed-in coordinator (from useCoordinator())
 *   • the stories strip has a "+" tile at the front to upload a story
 *     (limited to 1 per day per coordinator).
 */

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  ChevronDown, ChevronUp, ShieldCheck, Flame, ClipboardList, ThumbsUp,
  CheckCircle2, Trophy, Star, MapPin, Plus, LogOut, Search,
} from "lucide-react";
import { STORIES } from "@/lib/communityData";
import { useCoordinator } from "./CoordinatorProvider";
import { CONSTITUENCIES, shortAC } from "@/lib/constituencies";

function greetingFor(h) {
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

/* ── Brand wordmark: நம்குரல் in deep navy (crisp on the light frosted-glass
   header) with a gold signal-wave mark. ── */
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

/* ── Compact: constituency highlights (with + tile for the coordinator) ── */
function StoriesStrip({ onOpenStory, onAddStory, canUpload, coordinatorStories, constituency, onConstituency }) {
  return (
    <div className="pb-3">
      <div className="mb-2.5 flex items-center justify-between gap-2 px-0.5">
        <h2 className="text-[19px] font-extrabold tracking-tight text-slate-900">Constituency highlights</h2>
        {/* Constituency selector — pill on the right */}
        <div className="inline-flex shrink-0 items-center gap-1 rounded-full bg-white/90 py-1.5 pl-2.5 pr-1.5 ring-1 ring-slate-200 shadow-sm">
          <MapPin size={12} className="shrink-0 text-brand" />
          <div className="relative flex items-center">
            <select value={constituency} onChange={(e) => onConstituency(e.target.value)}
              className="max-w-[130px] cursor-pointer appearance-none truncate bg-transparent pr-4 text-[12px] font-bold text-slate-700 outline-none">
              {CONSTITUENCIES.map((c) => (<option key={c} value={c}>{shortAC(c)}</option>))}
            </select>
            <ChevronDown size={12} className="pointer-events-none absolute right-0 text-slate-400" />
          </div>
        </div>
      </div>

      <div className="no-scrollbar -mx-1 flex gap-3.5 overflow-x-auto px-1">
        {/* + tile — upload a story (1/day limit) — squircle + gold border */}
        <button
          onClick={onAddStory}
          disabled={!canUpload}
          title={canUpload ? "Upload a highlight" : "Daily limit reached — try again tomorrow"}
          className="flex w-[72px] shrink-0 flex-col items-center gap-1.5"
        >
          <span className={`relative flex h-[70px] w-[70px] items-center justify-center rounded-[22px] border-2 border-dashed ${canUpload ? "border-gold-300 bg-gold-100/60 text-slate-800" : "border-slate-300 bg-slate-100 text-slate-400"}`}>
            <Plus size={26} />
          </span>
          <span className={`line-clamp-2 text-center text-[10px] font-semibold leading-tight ${canUpload ? "text-slate-700" : "text-slate-400"}`}>
            {canUpload ? "Add highlight" : "1/day used"}
          </span>
        </button>

        {/* Coordinator's own recent uploads first — squircle + gold ring */}
        {coordinatorStories.slice(0, 3).map((s) => (
          <button key={s.id} onClick={() => onOpenStory({ id: s.id, label: "Yours", slides: [{ image: s.image, caption: s.caption || "" }] })}
            className="flex w-[72px] shrink-0 flex-col items-center gap-1.5">
            <span className="rounded-[22px] bg-gradient-to-br from-gold-200 via-gold-300 to-gold-400 p-[2.5px] shadow-sm">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s.image} alt="" className="h-[66px] w-[66px] rounded-[20px] border-2 border-white object-cover" />
            </span>
            <span className="line-clamp-2 text-center text-[10px] font-semibold leading-tight text-slate-600">Yours</span>
          </button>
        ))}

        {/* Curated highlights — squircle + thin gold gradient border (uniform) */}
        {STORIES.map((s) => (
          <button key={s.id} onClick={() => onOpenStory(s)} className="flex w-[72px] shrink-0 flex-col items-center gap-1.5">
            <span className="relative rounded-[22px] bg-gradient-to-br from-gold-200 via-gold-300 to-gold-400 p-[2.5px] shadow-sm">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s.slides[0].image} alt="" className="h-[66px] w-[66px] rounded-[20px] border-2 border-white object-cover" />
              {s.count > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-brand px-1 text-[10px] font-bold text-white ring-2 ring-white">{s.count}</span>
              )}
            </span>
            <span className="line-clamp-2 text-center text-[10px] font-semibold leading-tight text-slate-600">{s.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ── Expanded: coordinator profile panel (their own data) ── */
function ProfilePanel({ onCollapse, onLogout, me, publishedCount, verifiedCount }) {
  const greeting = greetingFor(new Date().getHours());
  const stats = [
    { icon: ClipboardList, value: publishedCount, label: "Published", tint: "text-brand bg-brand-50" },
    { icon: CheckCircle2, value: verifiedCount, label: "Verified", tint: "text-emerald-700 bg-emerald-50" },
    { icon: ThumbsUp, value: me.upvotes, label: "Upvotes", tint: "text-teal-700 bg-teal-50" },
    { icon: Trophy, value: me.tenure, label: "Tenure", tint: "text-slate-600 bg-slate-100" },
  ];

  return (
    <div className="pb-3">
      <div className="flex items-center gap-3">
        <div className="relative shrink-0">
          <div className="rounded-full bg-gradient-to-br from-gold-200 via-gold-300 to-gold-400 p-[3px]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={me.avatar} alt="" className="h-14 w-14 rounded-full border-2 border-white object-cover" />
          </div>
          <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-md bg-gradient-to-r from-slate-900 to-black px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide text-gold-200 ring-1 ring-gold-300/50 shadow">STAFF</span>
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-medium text-slate-400">{greeting},</p>
          <h2 className="truncate text-lg font-extrabold leading-tight text-slate-900">{me.name} 👋</h2>
          <span className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-teal-50 px-2 py-0.5 text-[10px] font-bold text-teal-700">
            <Flame size={10} className="fill-teal-500 text-teal-500" /> {me.role}
          </span>
        </div>
        <button onClick={onCollapse} className="self-start rounded-full p-1 text-slate-400 hover:bg-slate-200/60">
          <ChevronUp size={18} />
        </button>
      </div>

      {/* Premium black + gold — coordinator's signature card */}
      <div className="relative mt-3 overflow-hidden rounded-2xl bg-gradient-to-br from-slate-900 via-black to-slate-950 p-3.5 text-white shadow-[0_18px_45px_-16px_rgba(0,0,0,0.55)] ring-1 ring-gold-300/40">
        {/* subtle gold sheen */}
        <span className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-gold-300/15 blur-2xl" />
        <div className="relative flex items-end justify-between">
          <div>
            <p className="flex items-center gap-1 text-[11px] font-semibold text-gold-200"><ShieldCheck size={13} /> Coordinator Score</p>
            <div className="flex items-center gap-2">
              <p className="text-3xl font-black leading-none">{me.civicScore}</p>
              <span className="relative inline-flex items-center rounded-md bg-gradient-to-r from-gold-200 via-gold-300 to-gold-400 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-slate-900 shadow-[inset_0_1px_0_rgba(255,255,255,0.4),0_2px_6px_rgba(200,160,74,0.4)]">STAFF</span>
            </div>
          </div>
          <div className="text-right">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gold-200">Assigned</p>
            <p className="text-sm font-bold">{shortAC(me.constituency)}</p>
            <p className="text-[10px] text-slate-300">Ward {me.homeWard}</p>
          </div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-4 gap-2">
        {stats.map(({ icon: Icon, value, label, tint }) => (
          <div key={label} className="rounded-2xl bg-white/70 p-2 text-center ring-1 ring-white/60">
            <span className={`mx-auto flex h-7 w-7 items-center justify-center rounded-full ${tint}`}><Icon size={15} /></span>
            <p className="mt-1 text-sm font-extrabold leading-none text-slate-800">{value}</p>
            <p className="text-[9px] font-medium text-slate-500">{label}</p>
          </div>
        ))}
      </div>

      <button onClick={onLogout}
        className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-2xl border border-slate-200 bg-white/80 py-2.5 text-xs font-bold text-slate-600 hover:bg-white">
        <LogOut size={13} /> Sign out
      </button>
    </div>
  );
}

export default function CoordinatorHeader({
  progress, dragging, onOpenStory, onSetProgress, onCompact, onAddStory,
  constituency, onConstituency,
}) {
  const { me, state, feed, canUploadStory, logout } = useCoordinator();
  const storiesRef = useRef(null);
  const profileRef = useRef(null);
  const rootRef = useRef(null);
  const [heights, setHeights] = useState({ stories: 140, profile: 440 });

  useLayoutEffect(() => {
    const measure = () => {
      const s = storiesRef.current?.offsetHeight || 140;
      const pf = profileRef.current?.offsetHeight || 440;
      setHeights({ stories: s, profile: pf });
      onCompact?.((rootRef.current?.querySelector("[data-fixedhead]")?.offsetHeight || 78) + s);
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [onCompact]);

  if (!me) return null;

  const p = Math.max(0, Math.min(1, progress));
  const bodyH = heights.stories + (heights.profile - heights.stories) * p;
  const trans = dragging ? "none" : "height .55s cubic-bezier(.22,1,.36,1), opacity .4s ease, transform .55s cubic-bezier(.22,1,.36,1)";

  return (
    <div ref={rootRef} className="glass-clear absolute inset-x-0 top-0 z-30 rounded-b-[28px] shadow-[0_18px_40px_-20px_rgba(15,23,42,0.25)]">
      {/* Fixed head: status bar + logo/search/avatar bar (always visible) */}
      <div data-fixedhead>
        <div className="flex items-center justify-between px-5 pt-2.5 pb-1 text-[12px] font-semibold text-slate-800">
          <span>9:41</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
            <span className="tracking-tighter">5G</span>
            <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
          </span>
        </div>

        {/* logo bar */}
        <div className="flex items-center justify-between px-4 pb-2 pt-0.5">
          <BrandMark />
          <div className="flex items-center gap-2.5">
            <button aria-label="Search" className="flex h-9 w-9 items-center justify-center rounded-full text-slate-600 hover:bg-white/70">
              <Search size={20} />
            </button>
            {/* Coordinator avatar — shown only in the minimised view; fades out
                once the profile is expanded (redundant there). */}
            <button
              onClick={() => onSetProgress(1)}
              aria-label="Open profile"
              className="relative"
              style={{ opacity: 1 - Math.min(1, p * 2), pointerEvents: p > 0.4 ? "none" : "auto", transition: dragging ? "none" : "opacity .3s ease" }}
            >
              <span className="block rounded-full bg-gradient-to-br from-gold-200 via-gold-300 to-gold-400 p-[2px] shadow-sm">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={me.avatar} alt="" className="h-8 w-8 rounded-full border-2 border-white object-cover" />
              </span>
              <span className="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-white bg-emerald-500" />
            </button>
          </div>
        </div>
      </div>

      <div className="relative overflow-hidden rounded-b-[28px] px-4" style={{ height: bodyH, transition: trans }}>
        <div ref={storiesRef} className="absolute inset-x-4 top-0"
          style={{ opacity: 1 - Math.min(1, p * 1.4), transform: `translateY(${-p * 12}px)`, transition: trans, pointerEvents: p < 0.4 ? "auto" : "none" }}>
          <StoriesStrip
            onOpenStory={onOpenStory}
            onAddStory={onAddStory}
            canUpload={canUploadStory}
            coordinatorStories={(feed?.stories || []).filter((s) => s.author === me?.username)}
            constituency={constituency}
            onConstituency={onConstituency}
          />
        </div>
        <div ref={profileRef} className="absolute inset-x-4 top-0"
          style={{ opacity: Math.max(0, (p - 0.15) / 0.85), transform: `translateY(${(1 - p) * 14}px)`, transition: trans, pointerEvents: p > 0.6 ? "auto" : "none" }}>
          <ProfilePanel
            onCollapse={() => onSetProgress(0)}
            onLogout={logout}
            me={me}
            publishedCount={
              (feed?.posts || []).filter((p) => p.author === me?.username).length +
              (feed?.polls || []).filter((p) => p.author === me?.username).length
            }
            verifiedCount={state?.verifiedIds?.length || 0}
          />
        </div>
      </div>
    </div>
  );
}
