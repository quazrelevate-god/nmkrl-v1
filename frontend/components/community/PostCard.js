"use client";

/**
 * PostCard
 * --------
 * One community feed item, Reddit-style. A colour-coded flair pill + source +
 * time header, a title-first body, media / poll, meta chips, and an engagement
 * bar built around an up/down vote pill. The post's threaded comments render
 * inline beneath it (CommentSection); "View all" / the comment button open the
 * full CommentThread sheet.
 */

import { useState } from "react";
import {
  ArrowBigUp, ArrowBigDown, MessageCircle, Share2, Bookmark, MoreHorizontal,
  MapPin, Building2, Hash, Play, BarChart3,
} from "lucide-react";
import CommentSection from "./CommentSection";
import ShareSheet from "./ShareSheet";

/* Colour-coded flair pill derived from the post's kind/status. */
function flairFor(post) {
  if (post.status === "Official Update") return { label: "Update", cls: "bg-brand-100 text-brand-700" };
  if (post.status === "LIVE") return { label: "● LIVE", cls: "bg-rose-500 text-white" };
  if (post.type === "poll") return { label: "Poll", cls: "bg-violet-100 text-violet-700" };
  if (["Reported", "Escalated", "In Progress", "Resolved", "Assigned"].includes(post.status)) {
    return { label: "Issue", cls: "bg-rose-100 text-rose-600" };
  }
  return { label: "News", cls: "bg-slate-100 text-slate-600" };
}

function ImageGrid({ media }) {
  if (!media?.length) return null;
  if (media.length === 1) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={media[0]} alt="" className="mt-3 h-56 w-full rounded-2xl object-cover" />;
  }
  const shown = media.slice(0, 3);
  const extra = media.length - 3;
  return (
    <div className="mt-3 grid grid-cols-3 gap-1.5">
      {shown.map((m, i) => (
        <div key={i} className="relative">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={m} alt="" className="h-28 w-full rounded-xl object-cover" />
          {i === 2 && extra > 0 && (
            <div className="absolute inset-0 flex items-center justify-center rounded-xl bg-black/55 text-lg font-bold text-white">
              +{extra}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function VideoBlock({ post }) {
  const [playing, setPlaying] = useState(false);
  if (playing) {
    return (
      // eslint-disable-next-line jsx-a11y/media-has-caption
      <video src={post.video} poster={post.poster} controls autoPlay className="mt-3 h-56 w-full rounded-2xl bg-black object-cover" />
    );
  }
  return (
    <button onClick={() => setPlaying(true)} className="relative mt-3 block h-56 w-full overflow-hidden rounded-2xl">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={post.poster} alt="" className="h-full w-full object-cover" />
      <span className="absolute inset-0 flex items-center justify-center bg-black/25">
        <span className="flex h-14 w-14 items-center justify-center rounded-full bg-white/90 shadow-lg">
          <Play size={24} className="ml-1 fill-brand text-brand" />
        </span>
      </span>
    </button>
  );
}

function Poll({ post }) {
  const [voted, setVoted] = useState(null);
  const base = post.totalVotes || post.options.reduce((s, o) => s + o.votes, 0);
  const total = base + (voted != null ? 1 : 0);

  return (
    <div className="mt-3 space-y-2">
      {post.options.map((o, i) => {
        const votes = o.votes + (voted === i ? 1 : 0);
        const pct = Math.round((votes / total) * 100);
        const chosen = voted === i;
        return (
          <button
            key={i}
            onClick={() => setVoted(voted == null ? i : voted)}
            disabled={voted != null}
            className="relative block w-full overflow-hidden rounded-xl border border-slate-200 text-left"
          >
            <span
              className={`absolute inset-y-0 left-0 ease-spring transition-all duration-500 ${chosen ? "bg-brand/20" : "bg-slate-100"}`}
              style={{ width: voted != null ? `${pct}%` : "0%" }}
            />
            <span className="relative flex items-center justify-between px-3 py-2.5 text-sm">
              <span className={`font-medium ${chosen ? "text-brand" : "text-slate-700"}`}>
                {chosen && "✓ "}{o.label}
              </span>
              {voted != null && <span className="text-xs font-semibold text-slate-500">{votes} ({pct}%)</span>}
            </span>
          </button>
        );
      })}
      <div className="flex items-center justify-between pt-0.5">
        <span className="text-xs font-medium text-slate-500">{total} votes · {post.daysLeft} days left</span>
        {voted == null && (
          <span className="flex items-center gap-1 rounded-lg border border-slate-200 px-3 py-1 text-xs font-semibold text-brand">
            <BarChart3 size={13} /> Tap an option
          </span>
        )}
      </div>
    </div>
  );
}

/** Meta chip (location / department / ticket id). */
function Chip({ icon: Icon, children, tone = "slate" }) {
  const tones = {
    slate: "bg-slate-100 text-slate-600",
    brand: "bg-brand-50 text-brand",
    emerald: "bg-emerald-50 text-emerald-700",
  };
  return (
    <span className={`flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium ${tones[tone]}`}>
      <Icon size={11} /> {children}
    </span>
  );
}

export default function PostCard({ post, index = 0 }) {
  const [saved, setSaved] = useState(post.saved);
  const [voted, setVoted] = useState(0); // -1 down, 0 none, 1 up
  const [shares, setShares] = useState(post.shares || 0);
  const [expanded, setExpanded] = useState(false); // inline comments expanded
  const [showShare, setShowShare] = useState(false);

  const flair = flairFor(post);
  const commentCount = countComments(post.comments);
  const score = (post.likes || 0) + voted;
  const source = post.area || post.location || "Chennai";

  return (
    <div
      className="animate-fade-up"
      style={{ animationDelay: `${Math.min(index, 8) * 45}ms` }}
    >
      {/* ── ONE OUTER CARD enveloping the post section + comment section.
          The two inner white sections each cast a soft shadow, so the split
          reads as two panels held inside a single boundary. ── */}
      <div className="rounded-[26px] bg-slate-100/70 p-1.5 ring-1 ring-slate-200/70 shadow-[0_12px_34px_-18px_rgba(15,23,42,0.28)]">
      {/* ── POST SECTION ── */}
      <article className="rounded-[21px] bg-white p-4 shadow-[0_3px_14px_-6px_rgba(15,23,42,0.14)]">
        {/* Header: flair · source · time · menu */}
        <div className="flex items-center gap-2">
          <span className={`shrink-0 rounded-md px-2 py-0.5 text-[11px] font-bold ${flair.cls}`}>{flair.label}</span>
          {/* Moderation status pill — surfaces admin decisions on coordinator posts. */}
          {post.moderationStatus === "pending" && (
            <span className="shrink-0 rounded-full bg-amber-100 px-1.5 py-0.5 text-[9px] font-bold text-amber-800 ring-1 ring-amber-200">⏳ PENDING</span>
          )}
          {post.moderationStatus === "rejected" && (
            <span className="shrink-0 rounded-full bg-rose-100 px-1.5 py-0.5 text-[9px] font-bold text-rose-700 ring-1 ring-rose-200">✕ REJECTED</span>
          )}
          <p className="min-w-0 flex-1 truncate text-[12.5px] text-slate-400">
            <span className="font-semibold text-slate-500">{source}</span> · {post.time}
          </p>
          <button className="shrink-0 text-slate-300"><MoreHorizontal size={18} /></button>
        </div>

        {/* Title */}
        <h3 className="mt-2.5 text-[17px] font-extrabold leading-snug text-slate-900">
          {post.type === "poll" ? post.question : post.title}
        </h3>
        {post.body && <p className="mt-1.5 text-[14px] leading-relaxed text-slate-600">{post.body}</p>}

        {/* Media / poll */}
        {post.type === "image" && <ImageGrid media={post.media} />}
        {post.type === "video" && <VideoBlock post={post} />}
        {post.type === "poll"  && <Poll post={post} />}

        {/* Meta chips */}
        {post.type !== "poll" && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {post.location && <Chip icon={MapPin} tone="brand">{post.location}</Chip>}
            {post.tag && <Chip icon={Building2} tone="emerald">{post.tag}</Chip>}
            <Chip icon={Hash}>{post.id}</Chip>
          </div>
        )}

        {/* Engagement bar */}
        <div className="mt-3.5 flex items-center gap-2 border-t border-slate-200/70 pt-3">
          {/* Vote pill */}
          <div className="flex items-center gap-0.5 rounded-full bg-slate-100 px-1 py-0.5">
            <button
              onClick={() => setVoted((v) => (v === 1 ? 0 : 1))}
              className={`flex h-7 w-7 items-center justify-center rounded-full transition ${voted === 1 ? "text-orange-500" : "text-slate-500 hover:bg-white"}`}
              aria-label="Upvote"
            >
              <ArrowBigUp size={18} className={voted === 1 ? "fill-orange-500" : ""} />
            </button>
            <span className={`min-w-[30px] text-center text-sm font-bold ${voted === 1 ? "text-orange-500" : voted === -1 ? "text-indigo-500" : "text-slate-700"}`}>
              {score}
            </span>
            <button
              onClick={() => setVoted((v) => (v === -1 ? 0 : -1))}
              className={`flex h-7 w-7 items-center justify-center rounded-full transition ${voted === -1 ? "text-indigo-500" : "text-slate-500 hover:bg-white"}`}
              aria-label="Downvote"
            >
              <ArrowBigDown size={18} className={voted === -1 ? "fill-indigo-500" : ""} />
            </button>
          </div>

          {/* Comments — toggles the inline comment section below */}
          <button
            onClick={() => setExpanded((e) => !e)}
            className={`flex items-center gap-1.5 rounded-full px-3 py-2 text-sm font-semibold hover:bg-slate-100 ${expanded ? "text-brand" : "text-slate-500"}`}
          >
            <MessageCircle size={17} /> {commentCount}
          </button>

          {/* Share */}
          <button
            onClick={() => setShowShare(true)}
            className="flex items-center gap-1.5 rounded-full px-3 py-2 text-sm font-semibold text-slate-500 hover:bg-slate-100"
            aria-label="Share this post"
          >
            <Share2 size={17} /> Share
          </button>

          {/* Save */}
          <button
            onClick={() => setSaved((s) => !s)}
            className={`ml-auto flex h-9 w-9 items-center justify-center rounded-full hover:bg-slate-100 ${saved ? "text-brand" : "text-slate-400"}`}
            aria-label="Save post"
          >
            <Bookmark size={18} className={saved ? "fill-brand" : ""} />
          </button>
        </div>
      </article>

      {/* ── COMMENT SECTION (inline, constrained to this post) ── */}
      {commentCount > 0 && (
        <CommentSection post={post} expanded={expanded} onToggle={() => setExpanded((e) => !e)} />
      )}
      </div>

      <ShareSheet
        open={showShare}
        post={post}
        onClose={() => setShowShare(false)}
        onShared={() => setShares((s) => s + 1)}
      />
    </div>
  );
}

function countComments(nodes = []) {
  return nodes.reduce((s, n) => s + 1 + countComments(n.replies || []), 0);
}
