"use client";

/**
 * /admin/post-review — Content moderation queue.
 *
 * Coordinator-created posts and polls arrive here as "pending" and only reach
 * the citizen-facing feed after an admin accepts them. The console shows:
 *   • Three tabs — Pending / Approved / Rejected — with live counts
 *   • Per-item preview mirroring what the citizen will see (title, body,
 *     media, poll options, audience, hashtags)
 *   • One-click Accept, or Reject with a preset reason or custom note
 *   • A short-lived toast with Undo so mis-clicks are recoverable
 *
 * State is client-side (localStorage via lib/coordinators.js), so the demo
 * loop — coordinator writes → admin approves → coordinator sees badge flip —
 * works end-to-end without a backend.
 */

import { useEffect, useMemo, useState } from "react";
import {
  Megaphone, CheckCircle2, XCircle, Search, X, Filter, Undo2,
  MessageSquare, BarChart3, Clock, User, MapPin, Target, Hash,
  Sparkles, ChevronDown, Users, ShieldCheck, AlertOctagon,
} from "lucide-react";
import { COORDINATORS, listCoordinators } from "@/lib/coordinators";
import {
  listAll, approve, reject, revertToPending,
  MODERATION_EVENT, REJECT_PRESETS, seedDemoPosts,
} from "@/lib/postModeration";

const TABS = [
  { key: "pending",  label: "Pending",  icon: Clock,        tone: "text-amber-600" },
  { key: "approved", label: "Approved", icon: CheckCircle2, tone: "text-emerald-600" },
  { key: "rejected", label: "Rejected", icon: XCircle,      tone: "text-rose-500" },
];

const TYPE_TABS = [
  { key: "",     label: "All" },
  { key: "post", label: "Posts" },
  { key: "poll", label: "Polls" },
];

export default function PostReviewPage() {
  const [all, setAll] = useState([]);
  const [tab, setTab] = useState("pending");
  const [typeFilter, setTypeFilter] = useState("");
  const [authorFilter, setAuthorFilter] = useState("");
  const [query, setQuery] = useState("");
  const [toast, setToast] = useState(null);

  function refresh() { setAll(listAll()); }
  useEffect(() => {
    refresh();
    window.addEventListener(MODERATION_EVENT, refresh);
    const iv = setInterval(refresh, 5000);
    return () => {
      window.removeEventListener(MODERATION_EVENT, refresh);
      clearInterval(iv);
    };
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 4200);
    return () => clearTimeout(t);
  }, [toast]);

  const counts = useMemo(() => ({
    pending:  all.filter((x) => x.status === "pending").length,
    approved: all.filter((x) => x.status === "approved").length,
    rejected: all.filter((x) => x.status === "rejected").length,
  }), [all]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return all
      .filter((x) => x.status === tab)
      .filter((x) => !typeFilter || x.kind === typeFilter)
      .filter((x) => !authorFilter || x.author === authorFilter)
      .filter((x) => {
        if (!q) return true;
        const hay = [
          x.title, x.body, x.question,
          ...(x.options || []),
          ...(x.hashtags || []),
          ...(x.audience || []),
          x.location, x.author,
        ].filter(Boolean).join(" ").toLowerCase();
        return hay.includes(q);
      });
  }, [all, tab, typeFilter, authorFilter, query]);

  function handleApprove(item) {
    approve(item.id, item.kind);
    setToast({
      kind: "ok",
      msg: `Approved · ${itemHeadline(item)}`,
      undo: () => revertToPending(item.id, item.kind),
    });
  }
  function handleReject(item, reason) {
    reject(item.id, item.kind, { reason });
    setToast({
      kind: "err",
      msg: `Rejected · ${itemHeadline(item)}`,
      undo: () => revertToPending(item.id, item.kind),
    });
  }
  function handleRevert(item) {
    revertToPending(item.id, item.kind);
    setToast({ kind: "neutral", msg: `Moved back to pending`, undo: null });
  }

  return (
    <>
      {/* Header */}
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand">
            <Megaphone size={20} />
          </div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Post Review</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">
              Approve coordinator posts and polls before they reach citizens
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              const { added } = seedDemoPosts();
              setToast(added
                ? { kind: "neutral", msg: `Loaded ${added} demo posts and polls`, undo: null }
                : { kind: "neutral", msg: "Demo posts already loaded", undo: null });
            }}
            title="Populate the queue with realistic sample posts"
            className="glass-panel flex items-center gap-1.5 rounded-xl px-3 py-2 text-[11.5px] font-bold text-slate-600 hover:text-slate-800"
          >
            <Sparkles size={13} className="text-brand" /> Load samples
          </button>
          {counts.pending > 0 && (
            <span className="glass-panel flex items-center gap-2 rounded-xl px-3 py-2 text-[12px] font-bold text-amber-700 ring-1 ring-amber-200">
              <span className="h-2 w-2 animate-pulse rounded-full bg-amber-500" />
              {counts.pending} waiting
            </span>
          )}
        </div>
      </header>

      {/* Body */}
      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5">
        {/* Status tabs */}
        <div className="glass-panel mb-4 flex flex-wrap items-center gap-1 rounded-2xl p-1">
          {TABS.map((t) => {
            const Icon = t.icon;
            const active = tab === t.key;
            return (
              <button
                key={t.key}
                onClick={() => setTab(t.key)}
                className={`group flex items-center gap-2 rounded-xl px-3 py-2 text-[12.5px] font-bold transition ${
                  active
                    ? "accent-ring bg-gradient-to-r from-brand to-brand-dark text-white"
                    : "text-slate-600 hover:bg-slate-900/5"
                }`}
              >
                <Icon size={14} className={active ? "text-amber-300" : t.tone} />
                {t.label}
                <span className={`rounded-full px-1.5 text-[10.5px] font-bold ${
                  active ? "bg-amber-400 text-brand-dark" : "bg-slate-200 text-slate-600"
                }`}>
                  {counts[t.key]}
                </span>
              </button>
            );
          })}
        </div>

        {/* Toolbar */}
        <div className="glass-panel mb-4 flex flex-wrap items-center gap-2 rounded-2xl px-3 py-2.5">
          <div className="glass-panel flex min-w-[240px] flex-1 items-center gap-2.5 rounded-xl px-3 py-2">
            <Search size={16} className="text-slate-400" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search title, body, hashtag, or author"
              className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400"
            />
            {query && (
              <button onClick={() => setQuery("")} className="text-slate-400 hover:text-slate-600">
                <X size={14} />
              </button>
            )}
          </div>

          <select
            value={authorFilter}
            onChange={(e) => setAuthorFilter(e.target.value)}
            className="glass-panel h-10 min-w-[180px] rounded-xl bg-white/60 px-3 text-sm font-semibold text-slate-700 outline-none"
          >
            <option value="">All coordinators</option>
            {listCoordinators().map((c) => (
              <option key={c.username} value={c.username}>{c.name}</option>
            ))}
          </select>

          <div className="glass-panel flex items-center gap-1 rounded-xl p-1">
            {TYPE_TABS.map((t) => (
              <button
                key={t.key}
                onClick={() => setTypeFilter(t.key)}
                className={`rounded-lg px-2.5 py-1.5 text-[11px] font-bold transition ${
                  typeFilter === t.key
                    ? "bg-brand text-white shadow-sm"
                    : "text-slate-600 hover:bg-slate-900/5"
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>
        </div>

        {/* List */}
        {filtered.length ? (
          <div className="space-y-3">
            {filtered.map((item) => (
              <ReviewCard
                key={`${item.kind}-${item.id}`}
                item={item}
                onApprove={() => handleApprove(item)}
                onReject={(reason) => handleReject(item, reason)}
                onRevert={() => handleRevert(item)}
              />
            ))}
          </div>
        ) : (
          <EmptyState
            tab={tab}
            allEmpty={all.length === 0}
            onLoadSamples={() => {
              const { added } = seedDemoPosts();
              setToast(added
                ? { kind: "neutral", msg: `Loaded ${added} demo posts and polls`, undo: null }
                : { kind: "neutral", msg: "Demo posts already loaded", undo: null });
            }}
          />
        )}
      </div>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}
    </>
  );
}

/* ── Review card ─────────────────────────────────────────────────────────── */
function ReviewCard({ item, onApprove, onReject, onRevert }) {
  const author = COORDINATORS.find((c) => c.username === item.author) || {
    name: item.author, avatar: null, constituency: "", initials: (item.author || "?").slice(0, 2).toUpperCase(),
  };
  const isPending  = item.status === "pending";
  const isApproved = item.status === "approved";
  const isRejected = item.status === "rejected";

  return (
    <article className="glass-panel glass-hover rounded-2xl p-4">
      {/* Author strip */}
      <div className="flex flex-wrap items-center gap-2.5">
        <Avatar name={author.name} avatar={author.avatar} initials={author.initials} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className="truncate text-[13px] font-extrabold tracking-tight text-slate-800">{author.name}</p>
            <span className="font-mono text-[11px] text-slate-500">@{author.author || item.author}</span>
            {author.constituency && (
              <span className="rounded-full bg-brand/10 px-2 py-0.5 text-[10px] font-bold text-brand">
                {author.constituency}
              </span>
            )}
            {item.kind === "poll" ? (
              <span className="flex items-center gap-1 rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-bold text-violet-700">
                <BarChart3 size={10} /> POLL
              </span>
            ) : (
              <span className="flex items-center gap-1 rounded-full bg-sky-100 px-2 py-0.5 text-[10px] font-bold text-sky-700">
                <MessageSquare size={10} /> POST
              </span>
            )}
          </div>
          <p className="mt-0.5 flex items-center gap-1.5 text-[11px] text-slate-500">
            <Clock size={10} /> {relativeTime(item.submittedAt) || "Just submitted"}
            {item.location && <><span>·</span><MapPin size={10} /> {item.location}</>}
          </p>
        </div>
      </div>

      {/* Content preview */}
      <div className="mt-3 rounded-xl border border-slate-200/70 bg-white/60 p-3">
        {item.kind === "post" ? (
          <>
            {item.title && (
              <h3 className="text-[14px] font-extrabold leading-snug text-slate-900">{item.title}</h3>
            )}
            {item.body && (
              <p className="mt-1 whitespace-pre-line text-[13px] leading-relaxed text-slate-700">
                {item.body}
              </p>
            )}
            {item.media && item.mediaKind !== "video" && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={item.media} alt="attached media" className="mt-2 max-h-56 w-full rounded-xl object-cover" />
            )}
            {item.media && item.mediaKind === "video" && (
              <div className="mt-2 flex items-center gap-2 rounded-xl bg-slate-100 px-3 py-2 text-[12px] font-semibold text-slate-600">
                <Sparkles size={12} className="text-brand" /> Video attachment (plays for citizens)
              </div>
            )}
          </>
        ) : (
          <>
            <h3 className="text-[14px] font-extrabold leading-snug text-slate-900">{item.question}</h3>
            <ul className="mt-2 space-y-1.5">
              {(item.options || []).map((opt, i) => (
                <li key={i} className="rounded-lg bg-slate-100 px-3 py-1.5 text-[12.5px] font-semibold text-slate-700">
                  {String.fromCharCode(65 + i)}. {opt}
                </li>
              ))}
            </ul>
          </>
        )}

        {/* Chips: audience + hashtags */}
        {(item.audience?.length || item.hashtags?.length) ? (
          <div className="mt-3 flex flex-wrap items-center gap-1.5">
            {item.audience?.map((a) => (
              <span key={a} className="flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[10.5px] font-bold text-emerald-700 ring-1 ring-emerald-200">
                <Target size={10} /> {a}
              </span>
            ))}
            {item.hashtags?.map((h) => (
              <span key={h} className="flex items-center gap-0.5 rounded-full bg-slate-100 px-2 py-0.5 text-[10.5px] font-bold text-slate-600">
                <Hash size={10} /> {h}
              </span>
            ))}
          </div>
        ) : null}
      </div>

      {/* Decision area */}
      {isPending && (
        <div className="mt-3 flex items-center justify-end gap-2">
          <RejectMenu onReject={onReject} />
          <button
            onClick={onApprove}
            className="accent-ring flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-4 py-2 text-[12.5px] font-bold text-white shadow-lg shadow-emerald-500/30"
          >
            <CheckCircle2 size={14} /> Accept
          </button>
        </div>
      )}

      {isApproved && (
        <div className="mt-3 flex items-center justify-between rounded-xl bg-emerald-50 px-3 py-2 ring-1 ring-emerald-200">
          <div className="flex items-center gap-2 text-[11.5px] font-semibold text-emerald-800">
            <ShieldCheck size={13} />
            Approved · Now visible to citizens
            {item.reviewedAt && <span className="text-emerald-700/70">· {relativeTime(item.reviewedAt)}</span>}
          </div>
          <button
            onClick={onRevert}
            className="flex items-center gap-1 rounded-lg bg-white px-2.5 py-1 text-[10.5px] font-bold text-emerald-700 ring-1 ring-emerald-200 hover:bg-emerald-100"
          >
            <Undo2 size={11} /> Move back
          </button>
        </div>
      )}

      {isRejected && (
        <div className="mt-3 rounded-xl bg-rose-50 px-3 py-2 ring-1 ring-rose-200">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-[11.5px] font-semibold text-rose-800">
              <AlertOctagon size={13} />
              Rejected
              {item.reviewedAt && <span className="text-rose-700/70">· {relativeTime(item.reviewedAt)}</span>}
            </div>
            <button
              onClick={onRevert}
              className="flex items-center gap-1 rounded-lg bg-white px-2.5 py-1 text-[10.5px] font-bold text-rose-700 ring-1 ring-rose-200 hover:bg-rose-100"
            >
              <Undo2 size={11} /> Move back
            </button>
          </div>
          {item.rejectReason && (
            <p className="mt-1 text-[11.5px] italic text-rose-800/85">Reason: {item.rejectReason}</p>
          )}
        </div>
      )}
    </article>
  );
}

/* ── Reject-with-reason menu ─────────────────────────────────────────────── */
function RejectMenu({ onReject }) {
  const [open, setOpen] = useState(false);
  const [custom, setCustom] = useState("");
  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        onBlur={() => setTimeout(() => setOpen(false), 200)}
        className="flex items-center gap-1.5 rounded-xl border border-rose-200 bg-white px-3 py-2 text-[12.5px] font-bold text-rose-600 hover:bg-rose-50"
      >
        <XCircle size={14} /> Reject
        <ChevronDown size={12} />
      </button>
      {open && (
        <div
          className="animate-fade-up absolute right-0 top-full z-30 mt-1.5 w-72 overflow-hidden rounded-2xl bg-white shadow-xl ring-1 ring-slate-200"
          onMouseDown={(e) => e.preventDefault()}
        >
          <p className="border-b border-slate-100 px-3 py-2 text-[10px] font-bold uppercase tracking-wider text-slate-500">
            Reason for rejection
          </p>
          <div className="max-h-56 overflow-y-auto">
            {REJECT_PRESETS.map((preset) => (
              <button
                key={preset}
                onClick={() => { onReject(preset); setOpen(false); }}
                className="flex w-full items-start gap-2 px-3 py-2 text-left text-[12.5px] font-semibold text-slate-700 hover:bg-slate-50"
              >
                <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-rose-400" />
                {preset}
              </button>
            ))}
          </div>
          <div className="border-t border-slate-100 p-2">
            <textarea
              value={custom}
              onChange={(e) => setCustom(e.target.value)}
              rows={2}
              placeholder="Or write a custom reason…"
              className="w-full resize-none rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-[12px] outline-none focus:border-brand"
            />
            <div className="mt-1.5 flex items-center justify-end gap-1">
              <button
                onClick={() => { onReject(custom); setOpen(false); setCustom(""); }}
                disabled={!custom.trim()}
                className="rounded-lg bg-rose-500 px-3 py-1.5 text-[11px] font-bold text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-40"
              >
                Reject with reason
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Empty state ─────────────────────────────────────────────────────────── */
function EmptyState({ tab, allEmpty, onLoadSamples }) {
  const messages = {
    pending: {
      icon: CheckCircle2,
      title: allEmpty ? "Nothing in the queue yet" : "All caught up",
      body: allEmpty
        ? "Load a batch of realistic sample posts to walk through the moderation flow."
        : "No posts waiting for review. New coordinator submissions land here in real time.",
    },
    approved: {
      icon: Megaphone,
      title: "Nothing approved yet",
      body: "Accept a pending post to see it here.",
    },
    rejected: {
      icon: XCircle,
      title: "No rejections",
      body: "Rejected posts and their reasons will appear here for the record.",
    },
  };
  const m = messages[tab];
  const Icon = m.icon;
  const showSamplesCTA = tab === "pending" && allEmpty;
  return (
    <div className="glass-panel flex flex-col items-center justify-center gap-2 rounded-2xl py-14 text-center">
      <Icon size={34} className="text-slate-300" />
      <p className="text-sm font-extrabold text-slate-700">{m.title}</p>
      <p className="max-w-sm text-[12px] text-slate-500">{m.body}</p>
      {showSamplesCTA && (
        <button
          onClick={onLoadSamples}
          className="accent-ring mt-3 flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-brand to-brand-dark px-4 py-2 text-[12.5px] font-bold text-white shadow-lg shadow-brand/30"
        >
          <Sparkles size={13} className="text-amber-300" /> Load demo posts
        </button>
      )}
    </div>
  );
}

/* ── Toast with Undo ─────────────────────────────────────────────────────── */
function Toast({ toast, onDismiss }) {
  const styles = {
    ok:      "bg-emerald-600",
    err:     "bg-rose-600",
    neutral: "bg-slate-700",
  };
  return (
    <div className="animate-fade-up fixed bottom-6 right-6 z-50">
      <div className={`flex items-center gap-3 rounded-xl px-4 py-2.5 text-sm font-semibold text-white shadow-lg ${styles[toast.kind]}`}>
        <span>{toast.msg}</span>
        {toast.undo && (
          <button
            onClick={() => { toast.undo(); onDismiss(); }}
            className="flex items-center gap-1 rounded-lg bg-white/20 px-2 py-1 text-[11px] font-bold hover:bg-white/30"
          >
            <Undo2 size={11} /> Undo
          </button>
        )}
      </div>
    </div>
  );
}

/* ── Small utilities ─────────────────────────────────────────────────────── */
function Avatar({ name, avatar, initials }) {
  return avatar ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={avatar} alt={name} className="h-10 w-10 shrink-0 rounded-full object-cover ring-2 ring-white shadow-md" />
  ) : (
    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-brand to-brand-dark text-[12px] font-bold text-white shadow-md ring-2 ring-white">
      {initials || (name || "?").slice(0, 2).toUpperCase()}
    </div>
  );
}

function itemHeadline(item) {
  return (item.title || item.question || "post").slice(0, 44);
}

function relativeTime(iso) {
  if (!iso) return "";
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return "";
  const diff = Math.max(0, Date.now() - then);
  const s = Math.floor(diff / 1000);
  if (s < 60)  return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60)  return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24)  return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}
