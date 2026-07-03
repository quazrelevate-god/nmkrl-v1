"use client";

/**
 * StoriesHeader
 * -------------
 * Collapsible community header.
 *   • Collapsed → "Today's highlights" stories row + a slim greeting bar.
 *   • Expanded  → full citizen profile (civic score, rating, stats) plus
 *                 "Today's NEWS highlights". Toggled by the chevron, or by the
 *                 parent on an at-top scroll-up gesture.
 */

import {
  ChevronDown, ChevronUp, ShieldCheck, Star, ThumbsUp, Award, Users, Quote,
} from "lucide-react";
import { PROFILE, NEWS, STORIES } from "@/lib/communityData";

function greetingFor(h) {
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

function StoriesRow({ onOpenStory }) {
  return (
    <div className="no-scrollbar -mx-1 flex gap-3.5 overflow-x-auto px-1 pb-1">
      {STORIES.map(s => (
        <button key={s.id} onClick={() => onOpenStory(s)} className="flex w-16 shrink-0 flex-col items-center gap-1">
          <span className={`relative rounded-full bg-gradient-to-br ${s.ring} p-[2.5px]`}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={s.slides[0].image} alt="" className="h-[58px] w-[58px] rounded-full border-2 border-white object-cover" />
            {s.count > 0 && (
              <span className="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-rose-500 px-1 text-[10px] font-bold text-white ring-2 ring-white">
                {s.count}
              </span>
            )}
          </span>
          <span className="line-clamp-2 text-center text-[10px] font-medium leading-tight text-slate-600">{s.label}</span>
        </button>
      ))}
    </div>
  );
}

export default function StoriesHeader({ expanded, onToggle, onOpenStory }) {
  const greeting = greetingFor(new Date().getHours());

  return (
    <div className="glass ease-spring rounded-3xl p-3.5 shadow-sm transition-all duration-500">
      {!expanded ? (
        /* ── Collapsed: stories + slim greeting ── */
        <>
          <div className="mb-2.5 flex items-center gap-1.5 px-0.5">
            <Quote size={16} className="fill-brand text-brand" />
            <h2 className="text-sm font-extrabold text-slate-900">Today's highlights</h2>
            <button onClick={onToggle} className="ml-auto flex items-center gap-1 rounded-full bg-white/70 px-2.5 py-1 text-[11px] font-semibold text-slate-500">
              Profile <ChevronDown size={15} />
            </button>
          </div>
          <StoriesRow onOpenStory={onOpenStory} />
        </>
      ) : (
        /* ── Expanded: full profile + news ── */
        <div className="animate-fade-up">
          <div className="flex items-start gap-3">
            <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-gradient-to-b from-slate-200 to-slate-300">
              <Users size={26} className="text-slate-400" />
            </div>
            <div className="min-w-0 flex-1">
              <h2 className="text-lg font-extrabold leading-tight text-slate-900">{greeting}, {PROFILE.name}! 👋</h2>
              <p className="mt-0.5 text-xs leading-snug text-slate-500">
                Your dedicated contribution has directly enhanced more than <b className="text-slate-700">{PROFILE.streets}</b> local streets, public spaces, and community.
              </p>
              <p className="mt-0.5 text-xs font-medium text-green-600">We are grateful for your contribution for a better society — <span className="font-bold">CM</span></p>
            </div>
            <div className="shrink-0 rounded-xl border border-slate-200 bg-white/70 px-3 py-2 text-center">
              <div className="flex items-center justify-center gap-1 text-[11px] font-bold text-brand"><ShieldCheck size={13} /> Civic Score</div>
              <p className="text-2xl font-extrabold leading-tight text-green-600">{PROFILE.civicScore}</p>
            </div>
          </div>

          {/* Stat tiles */}
          <div className="mt-3 grid grid-cols-3 gap-2">
            <div className="rounded-xl bg-violet-50 px-2 py-2 text-center">
              <div className="flex items-center justify-center gap-1 text-[10px] font-semibold text-violet-600"><Users size={12} /> Rating</div>
              <div className="mt-0.5 flex justify-center gap-0.5">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Star key={i} size={11} className={i < Math.round(PROFILE.rating) ? "fill-green-500 text-green-500" : "fill-slate-300 text-slate-300"} />
                ))}
              </div>
            </div>
            <div className="rounded-xl bg-green-50 px-2 py-2 text-center">
              <ThumbsUp size={14} className="mx-auto text-green-600" />
              <p className="text-base font-extrabold leading-none text-slate-800">{PROFILE.upvotes}</p>
              <p className="text-[9px] font-medium text-slate-500">Upvotes Received</p>
            </div>
            <div className="rounded-xl bg-amber-50 px-2 py-2 text-center">
              <Award size={14} className="mx-auto text-amber-600" />
              <p className="text-sm font-extrabold leading-none text-amber-600">{PROFILE.tier}</p>
              <p className="text-[9px] font-medium text-slate-500">{PROFILE.tierLabel}</p>
            </div>
          </div>

          {/* News highlights */}
          <div className="relative mt-3 overflow-hidden rounded-2xl bg-slate-100/70 p-3">
            <div className="relative z-10">
              <p className="flex items-center gap-1.5 text-sm font-extrabold text-slate-900">
                <Quote size={15} className="fill-brand text-brand" /> {NEWS.title}
              </p>
              <p className="mt-1 text-xs leading-snug text-slate-600">
                {NEWS.body} — Together, we build a <span className="font-semibold text-brand">better Tamil Nadu</span>.
              </p>
            </div>
            <svg viewBox="0 0 120 90" className="pointer-events-none absolute -right-2 bottom-0 h-16 w-24 text-slate-300/70"
              fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round">
              <path d="M60 6 L74 20 H46 Z" /><path d="M50 20 h20 v6 h-20 z" /><path d="M46 26 L74 26 L70 38 H50 Z" />
              <path d="M44 38 h32 v6 h-32 z" /><path d="M40 44 L80 44 L76 58 H44 Z" /><path d="M36 58 h48 v6 h-48 z" />
              <path d="M32 64 h56 v22 h-56 z" /><path d="M54 74 h12 v12 h-12 z" />
            </svg>
          </div>

          <button onClick={onToggle} className="mx-auto mt-2 flex items-center justify-center rounded-full px-6 py-1 text-slate-400 hover:text-slate-600">
            <ChevronUp size={20} />
          </button>
        </div>
      )}
    </div>
  );
}
