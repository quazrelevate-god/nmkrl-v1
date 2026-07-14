"use client";

/**
 * TodaysPulse
 * -----------
 * Constituency-scoped "pulse" panel shown on the coordinator home (below
 * constituency highlights, above the community feed).
 *
 * Design — dark royal navy card with the MLA's portrait bleeding in on the
 * right at medium opacity. To keep text off the face, all textual content
 * (name, sentiment legend, summary, hashtags) is constrained to the left
 * column. KPI tiles float on the face on the right (their own glass fill
 * keeps them legible). The Tamil news carousel sits INSIDE the card, below
 * a divider, on a scrim that covers the face's lower portion so the news
 * cards read cleanly.
 */

import { useMemo } from "react";
import { TrendingUp, TrendingDown, ExternalLink, MapPin } from "lucide-react";
import { socialMentions, TAMIL_NEWS } from "@/lib/communityInsights";
import { shortAC } from "@/lib/constituencies";

const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

export default function TodaysPulse({ constituency }) {
  const social = useMemo(() => socialMentions(constituency), [constituency]);
  const up = social.trend >= 0;

  return (
    <section className="mt-3 px-4">
      <article className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#0e2545] via-[#0a1a35] to-[#050d1f] p-4 text-white shadow-[0_25px_60px_-20px_rgba(3,10,30,0.7)] ring-1 ring-white/10">
        {/* MLA portrait bleeds in from the right at medium opacity */}
        {social.image && (
          <div className="pointer-events-none absolute inset-y-0 right-0 w-[58%]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={social.image}
              alt=""
              className="h-full w-full object-cover object-top"
              style={{
                opacity: 0.55,
                WebkitMaskImage: "linear-gradient(to left, black 20%, rgba(0,0,0,0.6) 60%, transparent 100%)",
                maskImage: "linear-gradient(to left, black 20%, rgba(0,0,0,0.6) 60%, transparent 100%)",
              }}
            />
            {/* Subtle horizontal scrim over the face so any KPI/text overlay stays legible */}
            <div className="absolute inset-0 bg-gradient-to-l from-transparent via-[#0a1a35]/20 to-[#0a1a35]/60" />
          </div>
        )}

        {/* Bottom scrim — covers the face's lower portion so the news carousel below sits on a clean dark surface */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-[#050d1f] via-[#050d1f]/85 to-transparent" />

        {/* Header row */}
        <div className="relative z-10 flex items-center gap-2">
          <h2 className="text-base font-extrabold tracking-tight">Today's Pulse</h2>
          <span className="flex items-center gap-1 rounded-full border border-amber-400/50 bg-amber-500/10 px-2.5 py-0.5 text-[11px] font-bold text-amber-300">
            <MapPin size={11} /> {shortAC(constituency)}
          </span>
        </div>

        <div className="relative z-10 my-3 h-px bg-gradient-to-r from-white/20 via-white/10 to-transparent" />

        {/* Top body row: MLA identity on the left, KPI tiles floating on the face on the right */}
        <div className="relative z-10 flex items-start gap-3">
          <div className="min-w-0 flex-1 max-w-[60%]">
            <p className={`text-[18px] font-extrabold leading-tight ${social.pending ? "italic text-slate-300" : "text-white"}`}>
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

          {/* KPI grid — glass tiles float over the portrait */}
          <div className="grid w-[48%] shrink-0 grid-cols-2 gap-1.5">
            <KpiTile label="Mentions" value={fmt(social.mentions)} valueColor="text-amber-300" />
            <KpiTile label="Reach" value={`${social.reach}k`} valueColor="text-white" />
            <KpiTile label="Positive" value={`${social.pos}%`} valueColor="text-emerald-400" />
            <KpiTile label="Trend" value={`${up ? "+" : ""}${social.trend}%`}
              valueColor={up ? "text-emerald-400" : "text-rose-400"} icon={up ? TrendingUp : TrendingDown} />
          </div>
        </div>

        {/* Sentiment bar — constrained to the left column so the face stays clean */}
        <div className="relative z-10 mt-4 max-w-[62%]">
          <div className="flex h-2 overflow-hidden rounded-full bg-white/10">
            <span className="bg-emerald-500" style={{ width: `${social.pos}%` }} />
            <span className="bg-white/30" style={{ width: `${social.neu}%` }} />
            <span className="bg-rose-500" style={{ width: `${social.neg}%` }} />
          </div>
          <div className="mt-1 flex justify-between text-[10px] font-semibold">
            <span className="text-emerald-400">Pos {social.pos}%</span>
            <span className="text-slate-400">Neu {social.neu}%</span>
            <span className="text-rose-400">Neg {social.neg}%</span>
          </div>
        </div>

        {/* Summary — constrained to left column */}
        <p className="relative z-10 mt-3 max-w-[62%] text-[13px] leading-relaxed text-slate-200">
          {social.summary}
        </p>

        {/* Golden hashtag chips — constrained too so they don't wrap over the face */}
        <div className="relative z-10 mt-3 flex max-w-[62%] flex-wrap gap-1.5">
          {social.hashtags.map((h) => (
            <span key={h} className="rounded-full border border-amber-400/40 bg-amber-500/10 px-2.5 py-0.5 text-[11px] font-semibold text-amber-200">
              {h}
            </span>
          ))}
        </div>

        {/* Tamil news carousel — INSIDE the card, on the bottom scrim */}
        <div className="relative z-10 mt-4 border-t border-white/10 pt-3">
          <p className="mb-2 text-[10px] font-bold uppercase tracking-widest text-amber-300/80">
            Tamil news around this constituency
          </p>
          <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-1">
            {TAMIL_NEWS.map((n) => (
              <a key={n.id} href={n.url} target="_blank" rel="noopener noreferrer"
                className="group flex w-[200px] shrink-0 flex-col overflow-hidden rounded-2xl bg-white/10 ring-1 ring-white/15 backdrop-blur-sm transition hover:-translate-y-0.5 hover:bg-white/15">
                <div className="relative h-[110px] w-full overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={n.image} alt="" className="h-full w-full object-cover" />
                  <span className="absolute left-2 top-2 rounded-full bg-black/70 px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide text-white backdrop-blur">
                    {n.source}
                  </span>
                </div>
                <div className="flex flex-1 flex-col gap-1 p-2.5">
                  <p className="line-clamp-3 text-[12px] font-semibold leading-tight text-white">{n.title}</p>
                  <span className="mt-auto flex items-center gap-1 text-[10px] font-semibold text-amber-300 group-hover:underline">
                    Read <ExternalLink size={9} />
                  </span>
                </div>
              </a>
            ))}
          </div>
        </div>
      </article>
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
