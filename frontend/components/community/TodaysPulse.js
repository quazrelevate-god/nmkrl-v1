"use client";

/**
 * TodaysPulse
 * -----------
 * Constituency-scoped "pulse" panel shown on the coordinator home page (below
 * the constituency highlights, above the community feed).
 *
 * Design — dark royal navy card:
 *   • Left content column: constituency thumbnail, "Social Mentions · MLA"
 *     label in gold, the MLA's name, party chip.
 *   • Right side: the MLA's portrait fills the right half at medium opacity
 *     with a soft left-fade so it blends into the dark background. On top of
 *     that portrait sit four glass KPI tiles (Mentions / Reach / Positive /
 *     Trend).
 *   • Below: sentiment bar (green / gray / red) + summary paragraph + golden
 *     hashtag chips.
 *   • Below the card: a horizontal Tamil-news carousel.
 */

import { useMemo } from "react";
import { Radio, TrendingUp, TrendingDown, ExternalLink, MapPin } from "lucide-react";
import { socialMentions, TAMIL_NEWS } from "@/lib/communityInsights";
import { shortAC } from "@/lib/constituencies";

const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

/** Deterministic constituency landscape image for the little thumbnail tile. */
function landscapeFor(ac) {
  const seed = shortAC(ac).replace(/\s+/g, "-").toLowerCase();
  return `https://picsum.photos/seed/land-${seed}/220/220`;
}

export default function TodaysPulse({ constituency }) {
  const social = useMemo(() => socialMentions(constituency), [constituency]);
  const up = social.trend >= 0;
  const landscape = useMemo(() => landscapeFor(constituency), [constituency]);

  return (
    <section className="mt-3 space-y-3 px-4">
      {/* MLA card — royal navy with the MLA portrait blended on the right */}
      <article className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#0e2545] via-[#0a1a35] to-[#050d1f] p-4 text-white shadow-[0_25px_60px_-20px_rgba(3,10,30,0.7)] ring-1 ring-white/10">
        {/* MLA portrait, bleeds into the background from the right */}
        {social.image && (
          <div className="pointer-events-none absolute inset-y-0 right-0 w-[62%]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={social.image}
              alt=""
              className="h-full w-full object-cover object-top"
              style={{
                opacity: 0.55,
                WebkitMaskImage: "linear-gradient(to left, black 20%, rgba(0,0,0,0.55) 55%, transparent 95%)",
                maskImage: "linear-gradient(to left, black 20%, rgba(0,0,0,0.55) 55%, transparent 95%)",
              }}
            />
            {/* Extra dark scrim so text on top of the face stays legible */}
            <div className="absolute inset-0 bg-gradient-to-l from-transparent via-[#0a1a35]/30 to-[#0a1a35]/85" />
          </div>
        )}

        {/* Top header row */}
        <div className="relative z-10 flex items-center gap-2">
          <h2 className="text-base font-extrabold tracking-tight">Today's Pulse</h2>
          <span className="flex items-center gap-1 rounded-full border border-amber-400/50 bg-amber-500/10 px-2.5 py-0.5 text-[11px] font-bold text-amber-300">
            <MapPin size={11} /> {shortAC(constituency)}
          </span>
        </div>

        <div className="relative z-10 my-3 h-px bg-gradient-to-r from-white/20 via-white/10 to-transparent" />

        {/* Two-column body */}
        <div className="relative z-10 flex items-start gap-3">
          {/* Left column — thumbnail + label + name */}
          <div className="min-w-0 flex-1">
            <div className="h-[68px] w-[68px] overflow-hidden rounded-2xl ring-2 ring-white/10 shadow-lg">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={landscape} alt="" className="h-full w-full object-cover" />
            </div>
            <p className="mt-3 flex items-center gap-1 text-[10px] font-bold uppercase tracking-[0.15em] text-amber-300">
              <Radio size={11} /> Social Mentions · MLA
            </p>
            <p className={`mt-1 text-[17px] font-extrabold leading-tight ${social.pending ? "italic text-slate-300" : "text-white"}`}>
              {social.mla}
            </p>
            {social.party && (
              <span className={`mt-1 inline-flex items-center rounded-md px-2 py-0.5 text-[10px] font-black uppercase tracking-wide ${
                social.party === "DMK"
                  ? "bg-red-500/20 text-red-300 ring-1 ring-red-400/40"
                  : "bg-amber-400/25 text-amber-200 ring-1 ring-amber-400/50"
              }`}>{social.party}</span>
            )}
            <p className="mt-1 text-[11px] font-semibold text-slate-300">MLA · {shortAC(constituency)}</p>
          </div>

          {/* Right column — 2x2 KPI grid, floating on the portrait */}
          <div className="grid w-[48%] shrink-0 grid-cols-2 gap-1.5">
            <KpiTile label="Mentions" value={fmt(social.mentions)} valueColor="text-amber-300" />
            <KpiTile label="Reach" value={`${social.reach}k`} valueColor="text-white" />
            <KpiTile label="Positive" value={`${social.pos}%`} valueColor="text-emerald-400" />
            <KpiTile label="Trend" value={`${up ? "+" : ""}${social.trend}%`}
              valueColor={up ? "text-emerald-400" : "text-rose-400"} icon={up ? TrendingUp : TrendingDown} />
          </div>
        </div>

        {/* Sentiment bar */}
        <div className="relative z-10 mt-4 flex h-2 overflow-hidden rounded-full bg-white/10">
          <span className="bg-emerald-500" style={{ width: `${social.pos}%` }} />
          <span className="bg-white/30" style={{ width: `${social.neu}%` }} />
          <span className="bg-rose-500" style={{ width: `${social.neg}%` }} />
        </div>
        <div className="relative z-10 mt-1 flex justify-between text-[10px] font-semibold">
          <span className="text-emerald-400">Pos {social.pos}%</span>
          <span className="text-slate-400">Neu {social.neu}%</span>
          <span className="text-rose-400">Neg {social.neg}%</span>
        </div>

        {/* Summary paragraph */}
        <p className="relative z-10 mt-3 text-[13px] leading-relaxed text-slate-200">{social.summary}</p>

        {/* Golden hashtag chips */}
        <div className="relative z-10 mt-3 flex flex-wrap gap-1.5">
          {social.hashtags.map((h) => (
            <span key={h} className="rounded-full border border-amber-400/40 bg-amber-500/10 px-2.5 py-0.5 text-[11px] font-semibold text-amber-200">
              {h}
            </span>
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

/** Small glass KPI tile used on the right side of the pulse card. */
function KpiTile({ label, value, valueColor, icon: Icon }) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-right backdrop-blur-sm">
      <p className="text-[9px] font-bold uppercase tracking-widest text-slate-400">{label}</p>
      <p className={`flex items-center justify-end gap-0.5 text-[15px] font-extrabold ${valueColor}`}>
        {Icon && <Icon size={12} />}{value}
      </p>
    </div>
  );
}
