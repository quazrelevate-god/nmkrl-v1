"use client";

/**
 * CommunityHeader
 * ---------------
 * Fixed glass top bar for the Community feed. Its body morphs continuously
 * between the compact "Today's highlights" stories strip (progress 0) and the
 * full citizen profile (progress 1). The morph is driven in real time by the
 * parent's gesture/scroll `progress`; while `dragging` it follows the finger
 * 1:1 (no transition), and snaps with spring easing on release.
 */

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  ChevronDown, ChevronUp, ShieldCheck, Flame, ClipboardList, ThumbsUp,
  CheckCircle2, Trophy, Star,
} from "lucide-react";
import { PROFILE, STORIES } from "@/lib/communityData";

function greetingFor(h) {
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

/* ── Compact: stories strip ── */
function StoriesStrip({ onOpenStory, onExpand }) {
  return (
    <div className="pb-3">
      <div className="mb-2 flex items-center px-0.5">
        <h2 className="text-sm font-extrabold tracking-tight text-slate-900">Today's highlights</h2>
        <button onClick={onExpand} className="ml-auto flex items-center gap-1 rounded-full bg-white/70 px-2.5 py-1 text-[11px] font-semibold text-slate-500 ring-1 ring-white/60">
          Profile <ChevronDown size={14} />
        </button>
      </div>
      <div className="no-scrollbar -mx-1 flex gap-3.5 overflow-x-auto px-1">
        {STORIES.map(s => (
          <button key={s.id} onClick={() => onOpenStory(s)} className="flex w-16 shrink-0 flex-col items-center gap-1">
            <span className={`relative rounded-full bg-gradient-to-br ${s.ring} p-[2.5px]`}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s.slides[0].image} alt="" className="h-[56px] w-[56px] rounded-full border-2 border-white object-cover" />
              {s.count > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-rose-500 px-1 text-[10px] font-bold text-white ring-2 ring-white">{s.count}</span>
              )}
            </span>
            <span className="line-clamp-2 text-center text-[10px] font-medium leading-tight text-slate-600">{s.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ── Expanded: redesigned gamified profile ── */
function ProfilePanel({ onCollapse }) {
  const greeting = greetingFor(new Date().getHours());
  const pctInTier = Math.round(((PROFILE.levelSpan - PROFILE.toNext) / PROFILE.levelSpan) * 100);

  const stats = [
    { icon: ClipboardList, value: PROFILE.reports,  label: "Reports",  tint: "text-brand bg-brand-50" },
    { icon: ThumbsUp,      value: PROFILE.upvotes,  label: "Upvotes",  tint: "text-emerald-600 bg-emerald-50" },
    { icon: CheckCircle2,  value: PROFILE.resolved, label: "Resolved", tint: "text-violet-600 bg-violet-50" },
    { icon: Trophy,        value: PROFILE.rank,     label: "Rank",     tint: "text-amber-600 bg-amber-50" },
  ];

  return (
    <div className="pb-3">
      {/* Hero */}
      <div className="flex items-center gap-3">
        <div className="relative shrink-0">
          <div className="rounded-full bg-gradient-to-br from-amber-400 via-orange-500 to-rose-500 p-[3px]">
            <div className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-white bg-slate-100 text-xl font-black text-slate-500">
              {PROFILE.name.split(" ").map(w => w[0]).join("")}
            </div>
          </div>
          <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-full bg-amber-500 px-1.5 py-0.5 text-[8px] font-bold text-white shadow">{PROFILE.level}</span>
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-medium text-slate-400">{greeting},</p>
          <h2 className="truncate text-lg font-extrabold leading-tight text-slate-900">{PROFILE.name} 👋</h2>
          <span className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-700">
            <Flame size={10} className="fill-amber-500 text-amber-500" /> {PROFILE.streak}-day streak
          </span>
        </div>
        <button onClick={onCollapse} className="self-start rounded-full p-1 text-slate-400 hover:bg-slate-200/60">
          <ChevronUp size={18} />
        </button>
      </div>

      {/* Civic score + level progress */}
      <div className="mt-3 overflow-hidden rounded-2xl bg-gradient-to-br from-brand to-brand-dark p-3.5 text-white shadow-lg shadow-brand/25">
        <div className="flex items-end justify-between">
          <div>
            <p className="flex items-center gap-1 text-[11px] font-semibold text-rose-100"><ShieldCheck size={13} /> Civic Score</p>
            <p className="text-3xl font-black leading-none">{PROFILE.civicScore}</p>
          </div>
          <div className="text-right">
            <div className="flex justify-end gap-0.5">
              {Array.from({ length: 5 }).map((_, i) => (
                <Star key={i} size={12} className={i < Math.round(PROFILE.rating) ? "fill-amber-300 text-amber-300" : "fill-white/30 text-white/30"} />
              ))}
            </div>
            <p className="mt-0.5 text-[10px] text-rose-100">{PROFILE.rating}/5 rating</p>
          </div>
        </div>
        <div className="mt-2.5">
          <div className="mb-1 flex items-center justify-between text-[10px] font-medium text-rose-100">
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
          <div key={label} className="rounded-2xl bg-white/70 p-2 text-center ring-1 ring-white/60">
            <span className={`mx-auto flex h-7 w-7 items-center justify-center rounded-full ${tint}`}><Icon size={15} /></span>
            <p className="mt-1 text-sm font-extrabold leading-none text-slate-800">{value}</p>
            <p className="text-[9px] font-medium text-slate-500">{label}</p>
          </div>
        ))}
      </div>

      {/* Impact banner — a warm, motivating close to the profile */}
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
    </div>
  );
}

export default function CommunityHeader({ progress, dragging, onOpenStory, onSetProgress, onCompact }) {
  const storiesRef = useRef(null);
  const profileRef = useRef(null);
  const rootRef = useRef(null);
  const [heights, setHeights] = useState({ stories: 140, profile: 440 });

  useLayoutEffect(() => {
    const measure = () => {
      const s = storiesRef.current?.offsetHeight || 140;
      const pf = profileRef.current?.offsetHeight || 440;
      setHeights({ stories: s, profile: pf });
      // report compact total (status bar + stories body) up for scroll inset
      onCompact?.((rootRef.current?.querySelector("[data-status]")?.offsetHeight || 34) + s);
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [onCompact]);

  const p = Math.max(0, Math.min(1, progress));
  const bodyH = heights.stories + (heights.profile - heights.stories) * p;
  const trans = dragging
    ? "none"
    : "height .55s cubic-bezier(.22,1,.36,1), opacity .4s ease, transform .55s cubic-bezier(.22,1,.36,1)";

  return (
    <div ref={rootRef} className="glass-strong absolute inset-x-0 top-0 z-30 rounded-b-[28px] border-b border-white/50 shadow-[0_18px_45px_-14px_rgba(0,0,0,0.35)]">
      {/* status bar */}
      <div data-status className="flex items-center justify-between px-5 pt-2.5 pb-1 text-[12px] font-semibold text-slate-800">
        <span>9:41</span>
        <span className="flex items-center gap-1.5">
          <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
          <span className="tracking-tighter">5G</span>
          <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
        </span>
      </div>

      {/* morph body */}
      <div className="relative overflow-hidden rounded-b-[28px] px-4" style={{ height: bodyH, transition: trans }}>
        <div ref={storiesRef} className="absolute inset-x-4 top-0"
          style={{ opacity: 1 - Math.min(1, p * 1.4), transform: `translateY(${-p * 12}px)`, transition: trans, pointerEvents: p < 0.4 ? "auto" : "none" }}>
          <StoriesStrip onOpenStory={onOpenStory} onExpand={() => onSetProgress(1)} />
        </div>
        <div ref={profileRef} className="absolute inset-x-4 top-0"
          style={{ opacity: Math.max(0, (p - 0.15) / 0.85), transform: `translateY(${(1 - p) * 14}px)`, transition: trans, pointerEvents: p > 0.6 ? "auto" : "none" }}>
          <ProfilePanel onCollapse={() => onSetProgress(0)} />
        </div>
      </div>
    </div>
  );
}
