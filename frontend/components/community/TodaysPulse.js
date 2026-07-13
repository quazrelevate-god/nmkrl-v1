"use client";

/**
 * TodaysPulse
 * -----------
 * Constituency-scoped "pulse" panel shown on the citizen and coordinator home
 * feeds (below the constituency-highlights row, above the community posts).
 *
 * Contents:
 *   • MLA card — portrait photo above the name (illustrative), party chip,
 *     mentions / reach / trend KPIs, sentiment bar, hashtag chips.
 *   • Tamil news carousel — horizontally scrolling article thumbnails with
 *     source badges; opens the article URL in a new tab.
 *
 * Rerenders whenever the parent's `constituency` prop changes.
 */

import { useMemo } from "react";
import { Radio, TrendingUp, TrendingDown, ExternalLink } from "lucide-react";
import { socialMentions, TAMIL_NEWS } from "@/lib/communityInsights";
import { shortAC } from "@/lib/constituencies";

export default function TodaysPulse({ constituency }) {
  const social = useMemo(() => socialMentions(constituency), [constituency]);
  const up = social.trend >= 0;

  return (
    <section className="mt-3 space-y-3 px-4">
      <div className="flex items-center gap-2">
        <h2 className="text-sm font-extrabold tracking-tight text-slate-900">Today's Pulse</h2>
        <span className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-bold text-brand ring-1 ring-brand-100">
          {shortAC(constituency)}
        </span>
      </div>

      {/* MLA card */}
      <article className="glass overflow-hidden rounded-3xl p-4 ring-1 ring-white/60">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            {/* MLA image ABOVE the name (portrait, rounded-2xl) */}
            <div className="shrink-0">
              {social.image ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={social.image} alt="MLA portrait" className="h-16 w-16 rounded-2xl object-cover ring-2 ring-white shadow-sm" />
              ) : (
                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-slate-100 text-slate-400">—</div>
              )}
            </div>
            <div className="min-w-0">
              <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-widest text-brand">
                <Radio size={11} /> Social Mentions · MLA
              </p>
              <div className="mt-1 flex flex-wrap items-center gap-1.5">
                <p className={`text-base font-extrabold leading-tight ${social.pending ? "italic text-slate-400" : "text-slate-900"}`}>
                  {social.mla}
                </p>
                {social.party && (
                  <span className={`rounded-md px-1.5 py-0.5 text-[10px] font-bold ${
                    social.party === "DMK" ? "bg-red-100 text-red-700" : "bg-amber-100 text-amber-800"
                  }`}>{social.party}</span>
                )}
              </div>
              <p className="text-[11px] font-medium text-slate-500">MLA · {social.name}</p>
            </div>
          </div>
          {/* Corner KPIs */}
          <div className="grid shrink-0 grid-cols-2 gap-1 text-right">
            <MiniKpi label="Mentions" value={fmt(social.mentions)} tone="text-brand" />
            <MiniKpi label="Reach" value={`${social.reach}k`} tone="text-slate-800" />
            <MiniKpi label="Positive" value={`${social.pos}%`} tone="text-emerald-600" />
            <MiniKpi label="Trend" value={`${up ? "+" : ""}${social.trend}%`}
              tone={up ? "text-emerald-600" : "text-rose-500"} icon={up ? TrendingUp : TrendingDown} />
          </div>
        </div>

        {/* Sentiment bar */}
        <div className="mt-3 flex h-2 overflow-hidden rounded-full">
          <span className="bg-emerald-500" style={{ width: `${social.pos}%` }} />
          <span className="bg-slate-300" style={{ width: `${social.neu}%` }} />
          <span className="bg-rose-400" style={{ width: `${social.neg}%` }} />
        </div>
        <div className="mt-1 flex justify-between text-[10px] font-medium text-slate-400">
          <span>Pos {social.pos}%</span><span>Neu {social.neu}%</span><span>Neg {social.neg}%</span>
        </div>

        <p className="mt-2 text-[12px] leading-relaxed text-slate-600">{social.summary}</p>

        <div className="mt-2 flex flex-wrap gap-1.5">
          {social.hashtags.map((h) => (
            <span key={h} className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-semibold text-brand ring-1 ring-brand-100">{h}</span>
          ))}
        </div>
      </article>

      {/* Tamil news carousel */}
      <div>
        <p className="mb-1.5 px-0.5 text-[10px] font-bold uppercase tracking-widest text-slate-500">Tamil news around this constituency</p>
        <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-1">
          {TAMIL_NEWS.map((n) => (
            <a key={n.id} href={n.url} target="_blank" rel="noopener noreferrer"
              className="group flex w-[220px] shrink-0 flex-col overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200 transition hover:-translate-y-0.5 hover:shadow-md">
              <div className="relative h-[124px] w-full overflow-hidden">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={n.image} alt="" className="h-full w-full object-cover" />
                <span className="absolute left-2 top-2 rounded-full bg-black/60 px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide text-white backdrop-blur">
                  {n.source}
                </span>
              </div>
              <div className="flex flex-1 flex-col gap-1 p-2.5">
                <p className="line-clamp-3 text-[12px] font-semibold leading-tight text-slate-800">{n.title}</p>
                <span className="mt-auto flex items-center gap-1 text-[10px] font-semibold text-brand group-hover:underline">
                  Read <ExternalLink size={9} />
                </span>
              </div>
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}

function MiniKpi({ label, value, tone, icon: Icon }) {
  return (
    <div className="rounded-lg bg-white/60 px-2 py-1 ring-1 ring-white/60">
      <p className="text-[9px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
      <p className={`flex items-center justify-end gap-0.5 text-[13px] font-extrabold ${tone}`}>{Icon && <Icon size={11} />}{value}</p>
    </div>
  );
}

const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);
