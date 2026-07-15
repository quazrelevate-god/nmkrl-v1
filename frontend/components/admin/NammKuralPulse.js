"use client";

/**
 * NammKuralPulse
 * --------------
 * Editorial-style briefing section for the /admin/performance page — designed
 * to read like a personal PA morning digest for the MLA rather than a CRM
 * dashboard. Composed of five bands:
 *
 *   1. Signature banner (Tamil title, date, sentiment ribbon, weekly spark)
 *   2. "For the Hon'ble MLA" briefing card + Priority talking points
 *   3. Media coverage grid — 2 national + 4 Tamil regional outlets, each with
 *      thumbnail, extracted @mentions & reach, and outlet chip
 *   4. Social listening triptych — Instagram · Facebook · X (Twitter)
 *      with the top handle, top post excerpt, hashtag and engagement meter
 *   5. Voice of the constituency (citizen quote) alongside a hashtag cloud
 *
 * Data comes from `nammKuralPulse(ac)` in lib/communityInsights.js.
 */

import { useMemo, useState } from "react";
import {
  Radio, Sparkles, Newspaper, Megaphone, TrendingUp, ArrowUpRight, Quote,
  MessageCircle, ExternalLink, Flame, Bell,
} from "lucide-react";
import { nammKuralPulse } from "@/lib/communityInsights";

/* Inline platform glyphs — lucide 1.21.0 doesn't ship Instagram/Facebook/X
   marks, so we ship our own. */
function XLogo({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M18.244 2H21l-6.44 7.36L22 22h-6.828l-4.79-6.24L4.8 22H2l6.94-7.94L2 2h6.93l4.33 5.72L18.244 2Zm-2.394 18h1.874L7.222 4H5.24l10.61 16Z" />
    </svg>
  );
}
function InstagramLogo({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="3" y="3" width="18" height="18" rx="5" />
      <circle cx="12" cy="12" r="4" />
      <circle cx="17.5" cy="6.5" r="1" fill="currentColor" stroke="none" />
    </svg>
  );
}
function FacebookLogo({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M13.5 21v-7.5h2.55L16.5 10.5h-3v-2c0-.9.3-1.5 1.65-1.5H16.5V4.2c-.3-.05-1.35-.15-2.55-.15-2.55 0-4.2 1.5-4.2 4.35v2.1H7.5v3h2.25V21h3.75Z" />
    </svg>
  );
}

const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

const PLATFORM_STYLE = {
  Instagram: {
    Icon: InstagramLogo,
    accent: "from-pink-500 via-rose-500 to-amber-400",
    ring: "ring-rose-400/40",
    chip: "bg-rose-500/10 text-rose-200 ring-rose-400/40",
  },
  Facebook: {
    Icon: FacebookLogo,
    accent: "from-blue-500 via-sky-500 to-indigo-500",
    ring: "ring-sky-400/40",
    chip: "bg-sky-500/10 text-sky-200 ring-sky-400/40",
  },
  X: {
    Icon: XLogo,
    accent: "from-slate-100 via-slate-300 to-slate-100",
    ring: "ring-white/40",
    chip: "bg-white/10 text-white ring-white/30",
  },
};

export default function NammKuralPulse({ ac, isDefault }) {
  const data = useMemo(() => nammKuralPulse(ac), [ac]);
  const [tab, setTab] = useState("Instagram");

  const today = new Date().toLocaleDateString("en-IN", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  });

  return (
    <section aria-label="Namm Kural pulse" className="mt-4">
      <article
        className="relative overflow-hidden rounded-3xl p-6 text-white shadow-[0_30px_80px_-24px_rgba(3,10,30,0.65)] ring-1 ring-white/10"
        style={{
          background:
            "radial-gradient(120% 90% at 0% 0%, rgba(200,160,74,0.16) 0%, transparent 42%)," +
            "radial-gradient(140% 100% at 100% 100%, rgba(90,120,180,0.20) 0%, transparent 55%)," +
            "linear-gradient(160deg, #0e2545 0%, #0a1a35 50%, #050d1f 100%)",
        }}
      >
        {/* Decorative gold cornice */}
        <span className="pointer-events-none absolute inset-x-6 top-0 h-px bg-gradient-to-r from-transparent via-gold-300/60 to-transparent" />

        {/* ─────────────── 1. SIGNATURE BANNER ─────────────── */}
        <Banner data={data} today={today} isDefault={isDefault} />

        <Divider />

        {/* ─────────── 2. BRIEFING + TALKING POINTS ────────── */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.35fr_1fr]">
          <BriefingCard data={data} />
          <TalkingPoints points={data.talkingPoints} />
        </div>

        <Divider label="Media coverage" icon={Newspaper} tally={`${data.news.length} outlets today`} />

        {/* ─────────────── 3. NEWS GRID ─────────────── */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
          {data.news.map((n) => <NewsCard key={n.id} n={n} />)}
        </div>

        <Divider label="Social listening" icon={Radio} tally={`${fmt(data.buzz)} total mentions`} />

        {/* ─────────────── 4. SOCIAL TRIPTYCH ─────────────── */}
        <SocialTabs data={data} active={tab} onChange={setTab} />

        <Divider />

        {/* ─────────────── 5. VOICE + HASHTAG CLOUD ─────────────── */}
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1fr]">
          <VoiceCard voice={data.voice} shortName={data.shortName} />
          <HashtagCloud data={data} />
        </div>

        <p className="mt-6 flex items-center gap-2 text-[10px] italic text-slate-400">
          <Sparkles size={11} className="text-gold-300" />
          Illustrative feed — a live deployment would blend Meta / X APIs with a Tamil-news RSS + bot scraper, refreshed hourly.
        </p>
      </article>
    </section>
  );
}

/* ─────────────────────── SIGNATURE BANNER ─────────────────────── */
function Banner({ data, today, isDefault }) {
  return (
    <header className="relative z-10 flex flex-wrap items-start justify-between gap-4">
      <div className="flex items-start gap-4">
        {/* Signature medallion — same wave mark as the splash */}
        <div className="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-brand via-brand-dark to-[#05122a] ring-1 ring-gold-300/50">
          <svg viewBox="0 0 64 64" className="h-9 w-9" aria-hidden>
            <circle cx="18" cy="46" r="4.5" fill="#c8a04a" />
            <path d="M18 34 A22 22 0 0 1 40 56" fill="none" stroke="#c8a04a" strokeWidth="3"   strokeLinecap="round" />
            <path d="M18 24 A32 32 0 0 1 50 56" fill="none" stroke="#c8a04a" strokeWidth="2.5" strokeLinecap="round" />
            <path d="M18 14 A42 42 0 0 1 60 56" fill="none" stroke="#c8a04a" strokeWidth="2"   strokeLinecap="round" />
          </svg>
        </div>
        <div>
          <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-[0.28em] text-gold-300">
            <Radio size={11} /> Editorial briefing · Daily digest
          </p>
          <h2 className="mt-1 text-2xl font-black leading-tight tracking-tight text-white">
            நம் குரல் <span className="text-gold-200">pulse</span>
          </h2>
          <p className="mt-1 text-[12px] font-semibold text-slate-300">
            {today} · {data.shortName}
            {isDefault && <span className="ml-1 text-slate-500">(select a constituency to change)</span>}
          </p>
        </div>
      </div>

      {/* Sentiment ribbon + trend badge */}
      <div className="min-w-[260px] flex-1 max-w-md">
        <p className="mb-1.5 flex items-center justify-between text-[10px] font-bold uppercase tracking-widest text-slate-400">
          <span>Public sentiment today</span>
          <span className="flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 text-emerald-300 ring-1 ring-emerald-400/40">
            <TrendingUp size={11} /> +{data.trend}% wow
          </span>
        </p>
        <div className="flex h-2 overflow-hidden rounded-full">
          <span className="bg-emerald-500" style={{ width: `${data.posPct}%` }} />
          <span className="bg-slate-500/60" style={{ width: `${data.neuPct}%` }} />
          <span className="bg-rose-500" style={{ width: `${data.negPct}%` }} />
        </div>
        <div className="mt-1 flex justify-between text-[10px] font-semibold">
          <span className="text-emerald-400">Positive {data.posPct}%</span>
          <span className="text-slate-400">Neutral {data.neuPct}%</span>
          <span className="text-rose-400">Negative {data.negPct}%</span>
        </div>
        {/* 7-day spark */}
        <div className="mt-3">
          <div className="flex items-end gap-1 h-8">
            {data.spark.map((v, i) => (
              <span
                key={i}
                className="flex-1 rounded-t-sm"
                style={{
                  height: `${v}%`,
                  background: `linear-gradient(180deg, rgba(200,160,74,0.9) 0%, rgba(200,160,74,0.35) 100%)`,
                }}
                title={`Day ${i + 1}: ${v}`}
              />
            ))}
          </div>
          <p className="mt-1 text-[10px] font-semibold uppercase tracking-widest text-slate-500">7-day chatter volume</p>
        </div>
      </div>
    </header>
  );
}

/* ─────────────────────── BRIEFING CARD ─────────────────────── */
function BriefingCard({ data }) {
  return (
    <div className="relative overflow-hidden rounded-2xl bg-white/[0.04] p-5 ring-1 ring-white/10 backdrop-blur">
      <div className="flex items-start gap-4">
        {data.image && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={data.image}
            alt=""
            className="h-16 w-16 shrink-0 rounded-xl object-cover ring-2 ring-gold-300/70"
          />
        )}
        <div className="min-w-0 flex-1">
          <p className="text-[10px] font-bold uppercase tracking-[0.22em] text-gold-300">
            For the Hon'ble MLA
          </p>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <p className={`text-xl font-black leading-tight ${data.pending ? "italic text-slate-300" : "text-white"}`}>
              {data.mla}
            </p>
            {data.party && (
              <span className={`rounded-md px-1.5 py-0.5 text-[10px] font-black uppercase tracking-wide ${
                data.party === "DMK"
                  ? "bg-red-500/20 text-red-300 ring-1 ring-red-400/40"
                  : "bg-amber-400/25 text-amber-200 ring-1 ring-amber-400/50"
              }`}>{data.party}</span>
            )}
          </div>
          <p className="mt-3 text-[13.5px] leading-relaxed text-slate-100/90">
            {data.briefing}
          </p>
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────── TALKING POINTS ─────────────────────── */
function TalkingPoints({ points }) {
  return (
    <div className="rounded-2xl bg-gradient-to-br from-gold-500/[0.06] via-white/[0.03] to-transparent p-5 ring-1 ring-gold-300/25">
      <p className="mb-3 flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.22em] text-gold-300">
        <Bell size={11} /> Priority talking points · today
      </p>
      <ul className="space-y-2.5">
        {points.map((p, i) => (
          <li key={i} className="flex items-start gap-3 rounded-xl bg-white/[0.03] p-3 ring-1 ring-white/5">
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-gold-300/15 text-base ring-1 ring-gold-300/40">
              {p.icon}
            </span>
            <div className="min-w-0">
              <p className="text-[11px] font-bold uppercase tracking-wide text-gold-300">{p.label}</p>
              <p className="mt-0.5 text-[12.5px] leading-snug text-slate-200">{p.body}</p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

/* ─────────────────────── NEWS CARD ─────────────────────── */
function NewsCard({ n }) {
  return (
    <a
      href="#"
      className="group relative flex flex-col overflow-hidden rounded-2xl bg-white/[0.05] ring-1 ring-white/10 transition hover:-translate-y-0.5 hover:bg-white/[0.09] hover:ring-gold-300/40"
    >
      <div className="relative h-[110px] w-full overflow-hidden">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={n.image} alt="" className="h-full w-full object-cover transition group-hover:scale-[1.03]" />
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent" />
        {/* Outlet chip */}
        <div className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-black/70 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white backdrop-blur">
          <span
            className="grid h-4 w-4 place-items-center rounded-full text-[9px] font-black"
            style={{ background: n.tint, color: "#0a1a35" }}
          >
            {n.logo}
          </span>
          {n.outlet}
        </div>
        {/* Tier badge (National vs Tamil) */}
        <span className={`absolute right-2 top-2 rounded-full px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide backdrop-blur ${
          n.tier === "National" ? "bg-emerald-500/25 text-emerald-200 ring-1 ring-emerald-300/50" : "bg-amber-500/25 text-amber-100 ring-1 ring-amber-300/50"
        }`}>
          {n.tier}
        </span>
        {/* Reach + time strip along the bottom */}
        <div className="absolute inset-x-2 bottom-1.5 flex items-center justify-between text-[10px] font-bold text-white/85">
          <span className="flex items-center gap-1"><Flame size={10} className="text-rose-400" /> {n.reach}k reach</span>
          <span className="text-white/60">{n.time}</span>
        </div>
      </div>
      <div className="flex flex-1 flex-col gap-2 p-3">
        <p className="line-clamp-3 text-[12px] font-semibold leading-snug text-white">{n.headline}</p>
        <p className="line-clamp-2 text-[11px] text-slate-400">{n.snippet}</p>
        <div className="mt-auto flex flex-wrap gap-1 pt-1">
          {n.mentions.map((m) => (
            <span key={m} className="rounded-full bg-gold-300/10 px-2 py-0.5 text-[10px] font-semibold text-gold-200 ring-1 ring-gold-300/30">
              {m}
            </span>
          ))}
        </div>
        <span className="flex items-center gap-1 text-[10px] font-bold text-gold-300 opacity-0 transition group-hover:opacity-100">
          Read full <ExternalLink size={10} />
        </span>
      </div>
    </a>
  );
}

/* ─────────────────────── SOCIAL TRIPTYCH ─────────────────────── */
function SocialTabs({ data, active, onChange }) {
  const platforms = ["Instagram", "Facebook", "X"];
  return (
    <div>
      {/* Segmented tabs */}
      <div className="mb-4 flex items-center gap-1 rounded-xl bg-white/5 p-1 ring-1 ring-white/10 lg:hidden">
        {platforms.map((p) => {
          const style = PLATFORM_STYLE[p];
          const Icon = style.Icon;
          const isActive = p === active;
          return (
            <button
              key={p}
              onClick={() => onChange(p)}
              className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-[11px] font-bold transition ${
                isActive
                  ? `bg-gradient-to-r ${style.accent} text-brand-dark shadow`
                  : "text-slate-400"
              }`}
            >
              <Icon size={13} /> {p}
            </button>
          );
        })}
      </div>

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
        {platforms.map((p) => {
          const style = PLATFORM_STYLE[p];
          const record = data.social[p === "X" ? "x" : p.toLowerCase()];
          const isActiveMobile = p === active;
          return (
            <SocialColumn
              key={p}
              record={record}
              style={style}
              hiddenOnMobile={!isActiveMobile}
            />
          );
        })}
      </div>
    </div>
  );
}

function SocialColumn({ record, style, hiddenOnMobile }) {
  const { Icon } = style;
  return (
    <div className={`${hiddenOnMobile ? "hidden" : "flex"} lg:flex flex-col overflow-hidden rounded-2xl bg-white/[0.04] ring-1 ring-white/10`}>
      {/* Coloured header stripe */}
      <div className={`flex items-center justify-between bg-gradient-to-r ${style.accent} px-4 py-2.5 text-brand-dark`}>
        <div className="flex items-center gap-2">
          <Icon size={16} />
          <span className="text-[13px] font-black tracking-wide">{record.platform}</span>
        </div>
        <span className="text-[11px] font-black">
          {fmt(record.mentions)} <span className="font-semibold opacity-70">mentions</span>
        </span>
      </div>

      <div className="flex flex-1 flex-col gap-3 p-4">
        {/* Top handle */}
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Top handle</p>
          <p className="text-[13px] font-extrabold text-white">{record.topHandle}</p>
          <p className="text-[10px] text-slate-400">{record.followers} followers · leading {record.medium}</p>
        </div>

        {/* Top post excerpt */}
        <blockquote className="rounded-xl bg-white/[0.05] p-3 text-[12px] leading-snug text-slate-100 ring-1 ring-white/5">
          {record.topPost}
        </blockquote>

        {/* Hashtag + engagement meter */}
        <div className="mt-auto space-y-2.5">
          <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold ring-1 ${style.chip}`}>
            {record.topHashtag}
          </span>
          <div>
            <p className="mb-1 flex items-center justify-between text-[10px] font-bold uppercase tracking-widest text-slate-400">
              <span>Engagement rate</span>
              <span className="text-white">{record.engagement}%</span>
            </p>
            <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
              <div
                className={`h-full rounded-full bg-gradient-to-r ${style.accent}`}
                style={{ width: `${Math.min(100, record.engagement)}%` }}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────── VOICE CARD ─────────────────────── */
function VoiceCard({ voice, shortName }) {
  return (
    <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#0f2a4c] to-[#050f22] p-5 ring-1 ring-white/10">
      <Quote size={40} className="absolute -right-1 -top-1 text-gold-300/15" />
      <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-[0.22em] text-gold-300">
        <Megaphone size={11} /> Voice of {shortName}
      </p>
      <p className="mt-3 text-[15px] font-semibold leading-relaxed text-white">
        “{voice.text}”
      </p>
      <div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] font-semibold text-slate-300">
        <span className="text-white">{voice.author}</span>
        <span className="text-gold-200">{voice.handle}</span>
        <span className="text-slate-500">·</span>
        <span>{fmt(voice.likes)} likes</span>
        <span className="text-slate-500">·</span>
        <span>{voice.replies} replies</span>
        <span className="text-slate-500">·</span>
        <span>{voice.shares} shares</span>
      </div>
      <a href="#" className="mt-4 inline-flex items-center gap-1 rounded-lg bg-gold-300/15 px-3 py-1.5 text-[11px] font-bold text-gold-200 ring-1 ring-gold-300/40 transition hover:bg-gold-300/25">
        Draft a personal reply <ArrowUpRight size={12} />
      </a>
    </div>
  );
}

/* ─────────────────────── HASHTAG CLOUD ─────────────────────── */
function HashtagCloud({ data }) {
  const tags = [
    { tag: `#${data.social.instagram.topHashtag.replace(/^#/, "")}`, size: 20, color: "text-rose-300" },
    { tag: `#${data.social.x.topHashtag.replace(/^#/, "")}`,        size: 22, color: "text-white" },
    { tag: `#${data.social.facebook.topHashtag.replace(/^#/, "")}`, size: 15, color: "text-sky-300" },
    { tag: `#${data.shortName.replace(/\s+/g, "")}Rising`,          size: 14, color: "text-emerald-300" },
    { tag: `#WithMLA`,                                              size: 12, color: "text-gold-300" },
    { tag: "#NammKural",                                            size: 18, color: "text-gold-200" },
    { tag: `#${data.shortName.replace(/\s+/g, "")}Speaks`,          size: 13, color: "text-white" },
    { tag: "#MonsoonReady",                                         size: 12, color: "text-emerald-200" },
    { tag: "#GoodGovernance",                                       size: 14, color: "text-emerald-200" },
  ];
  return (
    <div className="relative overflow-hidden rounded-2xl bg-white/[0.03] p-5 ring-1 ring-white/10">
      <p className="mb-3 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-[0.22em] text-gold-300">
        <MessageCircle size={11} /> Trending around your name
      </p>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        {tags.map((t) => (
          <span
            key={t.tag}
            className={`font-black tracking-tight ${t.color}`}
            style={{ fontSize: `${t.size}px`, lineHeight: 1 }}
          >
            {t.tag}
          </span>
        ))}
      </div>
      <p className="mt-4 text-[11px] text-slate-400">
        Extracted from the last 24 h of X, Instagram &amp; Facebook posts tagged with your handle or your constituency.
      </p>
    </div>
  );
}

/* ─────────────────────── SHARED ─────────────────────── */
function Divider({ label, icon: Icon, tally }) {
  if (!label) return <div className="my-5 h-px bg-gradient-to-r from-transparent via-white/12 to-transparent" />;
  return (
    <div className="my-5 flex items-center gap-3">
      <span className="h-px flex-1 bg-gradient-to-r from-transparent to-gold-300/40" />
      <span className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-[0.28em] text-gold-300">
        {Icon && <Icon size={11} />} {label}
      </span>
      <span className="h-px w-24 bg-gold-300/40" />
      <span className="text-[10px] font-semibold text-slate-400">{tally}</span>
      <span className="h-px flex-1 bg-gradient-to-l from-transparent to-gold-300/40" />
    </div>
  );
}
