"use client";

/**
 * ProfileCard
 * -----------
 * Citizen profile / gamification header shown at the top of the Report screen.
 * Greeting (morning/afternoon/evening) is time-aware; the stats are demo values
 * for the PoC. Layout mirrors the provided reference: greeting + civic score,
 * a row of contribution stats, and a "Today's Motivation" quote.
 */

import {
  ClipboardList, ThumbsUp, Users, Award, ShieldCheck, Star, Quote, UserRound,
} from "lucide-react";

const STATS = [
  { icon: ClipboardList, value: "24",    label: "Grievances Submitted", cls: "bg-blue-50 text-brand" },
  { icon: ThumbsUp,      value: "56",    label: "Upvotes Received",     cls: "bg-green-50 text-green-600" },
  { icon: Users,         value: "4.8/5", label: "Contribution Rating",  cls: "bg-violet-50 text-violet-600" },
  { icon: Award,         value: "Top 15%", label: "Active Contributor", cls: "bg-amber-50 text-amber-600" },
];

function greetingFor(hour) {
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good eve";
}

export default function ProfileCard({ name = "Raj Kumar" }) {
  const greeting = greetingFor(new Date().getHours());

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      {/* Greeting + civic score */}
      <div className="flex items-start gap-3">
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-gradient-to-b from-slate-200 to-slate-300">
          <UserRound size={30} className="text-slate-400" />
        </div>

        <div className="min-w-0 flex-1">
          <h2 className="text-lg font-extrabold leading-tight text-slate-900">
            {greeting}, {name}! <span className="align-middle">👋</span>
          </h2>
          <p className="mt-0.5 text-xs leading-snug text-slate-500">
            Your contribution made 20+ streets and institutions better.
          </p>
          <p className="text-xs font-semibold text-brand">Thank you for making a difference!</p>
        </div>

        {/* Civic score */}
        <div className="shrink-0 rounded-xl border border-slate-200 bg-slate-50/60 px-3 py-2 text-center">
          <div className="flex items-center justify-center gap-1 text-[11px] font-semibold text-slate-600">
            <ShieldCheck size={13} className="text-brand" /> Civic Score
          </div>
          <p className="text-2xl font-extrabold leading-tight text-green-600">850</p>
          <p className="text-[10px] font-semibold text-green-600">Excellent</p>
          <div className="mt-0.5 flex justify-center gap-0.5">
            {Array.from({ length: 5 }).map((_, i) => (
              <Star key={i} size={11} className="fill-green-500 text-green-500" />
            ))}
          </div>
        </div>
      </div>

      {/* Stat cards */}
      <div className="mt-4 grid grid-cols-4 gap-2">
        {STATS.map(({ icon: Icon, value, label, cls }) => (
          <div key={label} className={`flex flex-col items-center gap-1 rounded-xl px-1.5 py-3 text-center ${cls}`}>
            <Icon size={18} />
            <span className="text-base font-extrabold leading-none">{value}</span>
            <span className="text-[9px] font-medium leading-tight text-slate-500">{label}</span>
          </div>
        ))}
      </div>

      {/* Today's Motivation */}
      <div className="relative mt-4 overflow-hidden rounded-xl border border-slate-100 bg-slate-50/70 p-3">
        <div className="relative z-10 flex gap-2.5">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-blue-50">
            <Quote size={16} className="fill-brand text-brand" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-bold text-slate-800">Today's Motivation</p>
            <p className="mt-0.5 text-xs leading-snug text-slate-600">
              Small actions, when multiplied by millions of citizens, can transform our communities.
            </p>
            <p className="mt-1 text-xs text-slate-600">
              — Together, we build a <span className="font-semibold text-brand">better Tamil Nadu</span>.
            </p>
          </div>
        </div>

        {/* Faint temple / gopuram watermark */}
        <svg
          viewBox="0 0 120 90"
          className="pointer-events-none absolute -right-2 bottom-0 h-16 w-24 text-slate-200"
          fill="none" stroke="currentColor" strokeWidth="2"
          strokeLinejoin="round" strokeLinecap="round"
        >
          <path d="M60 6 L74 20 H46 Z" />
          <path d="M50 20 h20 v6 h-20 z" />
          <path d="M46 26 L74 26 L70 38 H50 Z" />
          <path d="M44 38 h32 v6 h-32 z" />
          <path d="M40 44 L80 44 L76 58 H44 Z" />
          <path d="M36 58 h48 v6 h-48 z" />
          <path d="M32 64 h56 v22 h-56 z" />
          <path d="M54 74 h12 v12 h-12 z" />
        </svg>
      </div>
    </section>
  );
}
