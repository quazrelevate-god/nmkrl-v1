"use client";

/**
 * CommunityPulse
 * --------------
 * What the citizen community is actually doing in the app.
 *
 * This replaces the media-and-social-listening briefing. Phase 1 ingests no
 * news feeds and no social platforms, so that section was showing invented
 * coverage and invented handles as if they had been observed. Everything here
 * is counted from the same community feed the citizens read: posts, polls,
 * comment threads, and whether an official ever replied.
 *
 * The section leads with the one number a civic office should be judged on —
 * how many conversations got an official answer — and ends with the threads
 * still waiting for one, because that is the part someone can act on today.
 */

import { useMemo } from "react";
import {
  Sparkles, MessageCircle, Users, BarChart3, Heart, Share2,
  CheckCircle2, AlertCircle, CornerDownRight, MapPin, Vote,
} from "lucide-react";
import { communityPulse } from "@/lib/communityInsights";
import { ChartCard, RankedTable, VIZ } from "@/components/admin/charts";
import { shortAC } from "@/lib/constituencies";

const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

const ROLE_LABELS = {
  resident: "Residents",
  volunteer: "Volunteers",
  official: "Officials",
  reporter: "Reporters",
};

export default function CommunityPulse({ ac = "" }) {
  const p = useMemo(() => communityPulse(ac), [ac]);
  const scopeLabel = ac ? shortAC(ac) : "All constituencies";

  if (!p.posts) {
    return (
      <div className="rounded-2xl border border-slate-200 bg-white p-8 text-center">
        <Sparkles size={28} className="mx-auto mb-2 text-slate-300" />
        <p className="text-sm font-semibold text-slate-600">No community activity in {scopeLabel} yet.</p>
        <p className="text-[12px] text-slate-400">Posts, polls and comment threads will appear here as citizens use the feed.</p>
      </div>
    );
  }

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-2 pt-1 text-sm font-extrabold text-slate-700">
          <Sparkles size={16} className="text-brand" />
          Community pulse · {scopeLabel}
          <span className="text-[11px] font-medium normal-case text-slate-400">
            — posts, polls and threads from the citizen feed
          </span>
        </p>
      </div>

      {/* ── The headline: are conversations getting answered? ── */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)]">
        <div className="rounded-2xl border border-slate-200 bg-white p-5">
          <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
            Official response rate
          </p>
          <p className="mt-1 flex items-baseline gap-2">
            <span className="text-[44px] font-extrabold leading-none tabular-nums text-slate-900">
              {p.responseRate}
            </span>
            <span className="text-xl font-bold text-slate-400">%</span>
          </p>
          <p className="mt-1.5 text-[12px] text-slate-500">
            {p.answeredThreads} of {p.posts} discussions have a reply from an official account.
          </p>
          <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
            <div className="h-full rounded-full transition-[width] duration-500"
              style={{ width: `${p.responseRate}%`, background: p.responseRate >= 60 ? VIZ.series2 : VIZ.medium }} />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <Tile label="Posts" value={p.posts} icon={MessageCircle} />
          <Tile label="Comments" value={fmt(p.comments)} icon={CornerDownRight} />
          <Tile label="Distinct voices" value={p.voices} icon={Users} />
          <Tile label="Poll votes" value={fmt(p.pollVotes)} icon={BarChart3} />
          <Tile label="Likes" value={fmt(p.likes)} icon={Heart} />
          <Tile label="Shares" value={fmt(p.shares)} icon={Share2} />
        </div>
      </div>

      {/* ── Polls: where the community stated a preference outright ── */}
      {p.polls.length > 0 && (
        <ChartCard
          title="Open polls"
          subtitle={`${p.polls.length} running · ${fmt(p.pollVotes)} votes cast`}
        >
          <div className="space-y-5">
            {p.polls.map((poll) => (
              <div key={poll.id}>
                <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
                  <p className="text-[13px] font-bold text-slate-800">{poll.question}</p>
                  <p className="flex items-center gap-2 text-[11px] text-slate-400">
                    <span className="flex items-center gap-1"><MapPin size={10} /> {poll.area}</span>
                    <span className="tabular-nums">{fmt(poll.total)} votes</span>
                    {poll.daysLeft != null && (
                      <span className="rounded-full bg-amber-50 px-1.5 py-0.5 font-bold text-amber-700">
                        {poll.daysLeft}d left
                      </span>
                    )}
                  </p>
                </div>
                <div className="space-y-1.5">
                  {poll.options.map((o, i) => (
                    <div key={o.label} className="flex items-center gap-3">
                      <span className="min-w-0 flex-1">
                        <span className="mb-1 block truncate text-[12px] text-slate-600">{o.label}</span>
                        <span className="block h-1.5 overflow-hidden rounded-full bg-slate-100">
                          <span className="block h-full rounded-full transition-[width] duration-500"
                            style={{ width: `${o.pct}%`, background: i === 0 ? VIZ.series1 : "#c7d5e8" }} />
                        </span>
                      </span>
                      <span className="w-11 shrink-0 text-right text-[12px] font-bold tabular-nums text-slate-700">
                        {o.pct}%
                      </span>
                    </div>
                  ))}
                </div>
                <p className="mt-1.5 text-[11px] text-slate-400">
                  {poll.margin >= 20
                    ? `Clear preference — ${poll.margin} points ahead of the next option.`
                    : `Split opinion — only ${poll.margin} points between the top two.`}
                </p>
              </div>
            ))}
          </div>
        </ChartCard>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* ── Who is doing the talking ── */}
        <ChartCard title="Who is in the threads" subtitle={`${p.replies} of ${p.comments} comments are replies — ${p.replyDepth} levels deep`}>
          <RankedTable
            rows={Object.entries(p.byRole)
              .map(([k, v]) => ({ label: ROLE_LABELS[k] || k, value: v }))
              .sort((a, b) => b.value - a.value)}
            headers={["Participant", "Comments", "Share"]}
            empty="No comments yet"
          />
        </ChartCard>

        {/* ── Where the conversation is ── */}
        <ChartCard title="Most active areas" subtitle="Posts by neighbourhood">
          <RankedTable rows={p.areas} headers={["Area", "Posts", "Share"]} empty="No located posts" />
        </ChartCard>
      </div>

      {/* ── The actionable end: threads with nobody official in them ── */}
      <ChartCard
        title="Waiting for an official reply"
        subtitle="Busiest discussions with no response from a verified account"
        right={
          p.unanswered.length === 0 ? (
            <span className="flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-[11px] font-bold text-emerald-700">
              <CheckCircle2 size={12} /> All answered
            </span>
          ) : (
            <span className="flex items-center gap-1.5 rounded-full bg-amber-50 px-2.5 py-1 text-[11px] font-bold text-amber-700">
              <AlertCircle size={12} /> {p.unanswered.length} open
            </span>
          )
        }
      >
        {p.unanswered.length === 0 ? (
          <p className="py-8 text-center text-xs text-slate-400">
            Every discussion in {scopeLabel} has had an official reply.
          </p>
        ) : (
          <ul className="divide-y divide-slate-100">
            {p.unanswered.map((t) => (
              <li key={t.id} className="flex items-start gap-3 py-2.5 first:pt-0 last:pb-0">
                <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-amber-50 text-amber-700">
                  {t.type === "poll" ? <Vote size={13} /> : <MessageCircle size={13} />}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[13px] font-semibold text-slate-800">{t.title}</span>
                  <span className="text-[11px] text-slate-400">{t.area}</span>
                </span>
                <span className="shrink-0 text-right">
                  <span className="block text-[13px] font-bold tabular-nums text-slate-800">{t.comments}</span>
                  <span className="text-[10px] uppercase tracking-wide text-slate-400">comments</span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </ChartCard>
    </section>
  );
}

function Tile({ label, value, icon: Icon }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4">
      <p className="mb-1.5 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400">
        <Icon size={12} /> {label}
      </p>
      <p className="text-[22px] font-extrabold leading-none tabular-nums text-slate-900">{value}</p>
    </div>
  );
}
