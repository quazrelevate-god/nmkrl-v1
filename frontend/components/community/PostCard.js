"use client";

/**
 * PostCard
 * --------
 * One community feed item. Supports text / image / video / poll bodies with
 * Like, Comment (opens the threaded sheet), Share and Save actions.
 */

import { useState } from "react";
import {
  ThumbsUp, MessageCircle, Share2, Bookmark, MoreHorizontal,
  MapPin, Hash, BadgeCheck, Play, BarChart3,
} from "lucide-react";
import { STATUS_STYLE } from "@/lib/communityData";
import CommentThread from "./CommentThread";

function ImageGrid({ media }) {
  if (!media?.length) return null;
  if (media.length === 1) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={media[0]} alt="" className="mt-2 h-52 w-full rounded-xl object-cover" />;
  }
  const shown = media.slice(0, 3);
  const extra = media.length - 3;
  return (
    <div className={`mt-2 grid gap-1.5 ${media.length === 2 ? "grid-cols-2" : "grid-cols-3"}`}>
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
      <video src={post.video} poster={post.poster} controls autoPlay className="mt-2 h-52 w-full rounded-xl bg-black object-cover" />
    );
  }
  return (
    <button onClick={() => setPlaying(true)} className="relative mt-2 block h-52 w-full overflow-hidden rounded-xl">
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
    <div className="mt-2 space-y-2">
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

export default function PostCard({ post, index = 0 }) {
  const [liked, setLiked] = useState(false);
  const [saved, setSaved] = useState(post.saved);
  const [likes, setLikes] = useState(post.likes);
  const [shares, setShares] = useState(post.shares || 0);
  const [showComments, setShowComments] = useState(false);
  const commentCount = countComments(post.comments);

  function toggleLike() {
    setLiked(l => !l);
    setLikes(n => n + (liked ? -1 : 1));
  }

  return (
    <>
      <article
        className="glass animate-fade-up rounded-3xl p-4 shadow-sm"
        style={{ animationDelay: `${Math.min(index, 8) * 45}ms` }}
      >
        {/* Author */}
        <div className="flex items-center gap-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={post.avatar} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1">
              <span className="truncate text-sm font-bold text-slate-900">{post.author}</span>
              {post.verified && <BadgeCheck size={14} className="shrink-0 text-brand" />}
              {post.type === "poll" && (
                <span className="ml-1 flex items-center gap-0.5 rounded-full bg-violet-100 px-1.5 py-0.5 text-[9px] font-bold text-violet-600">
                  <BarChart3 size={9} /> POLL
                </span>
              )}
            </div>
            <p className="flex items-center gap-1 text-[11px] font-medium text-green-600">
              <MapPin size={10} /> {[post.area, post.handle].filter(Boolean).join(" · ")}
            </p>
          </div>
          <span className="shrink-0 text-[11px] text-slate-400">{post.time}</span>
          <button className="text-slate-300"><MoreHorizontal size={18} /></button>
        </div>

        {/* Status + title */}
        <div className="mt-2.5">
          {post.type === "poll" ? (
            <>
              <h3 className="text-[15px] font-bold leading-snug text-slate-900">{post.question}</h3>
              {post.body && <p className="mt-1 text-sm leading-snug text-slate-600">{post.body}</p>}
            </>
          ) : (
            <>
              <div className="flex items-center gap-2">
                {post.status && (
                  <span className={`rounded-md px-2 py-0.5 text-[11px] font-bold ${STATUS_STYLE[post.status] || "bg-slate-100 text-slate-600"}`}>
                    {post.status}
                  </span>
                )}
                <h3 className="text-[15px] font-bold leading-snug text-slate-900">{post.title}</h3>
              </div>
              {post.body && <p className="mt-1 text-sm leading-snug text-slate-600">{post.body}</p>}
            </>
          )}
        </div>

        {/* Body media */}
        {post.type === "image" && <ImageGrid media={post.media} />}
        {post.type === "video" && <VideoBlock post={post} />}
        {post.type === "poll"  && <Poll post={post} />}

        {/* Meta chips */}
        {post.type !== "poll" && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {post.location && (
              <span className="flex items-center gap-1 rounded-full bg-brand-50 px-2.5 py-1 text-[11px] font-medium text-brand">
                <MapPin size={11} /> {post.location}
              </span>
            )}
            {post.tag && (
              <span className="rounded-full bg-rose-50 px-2.5 py-1 text-[11px] font-medium text-rose-600">{post.tag}</span>
            )}
            <span className="flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-medium text-slate-500">
              <Hash size={10} /> {post.id}
            </span>
          </div>
        )}

        {/* Engagement */}
        <div className="mt-3 flex items-center justify-between border-t border-slate-200/70 pt-2.5 text-slate-500">
          <button onClick={toggleLike} className={`flex items-center gap-1.5 text-sm font-medium ${liked ? "text-brand" : ""}`}>
            <ThumbsUp size={17} className={liked ? "fill-brand" : ""} /> {likes}
          </button>
          <button onClick={() => setShowComments(true)} className="flex items-center gap-1.5 text-sm font-medium">
            <MessageCircle size={17} /> {commentCount}
          </button>
          <button onClick={() => setShares(s => s + 1)} className="flex items-center gap-1.5 text-sm font-medium">
            <Share2 size={17} /> {shares}
          </button>
          <button onClick={() => setSaved(s => !s)} className={saved ? "text-brand" : ""}>
            <Bookmark size={17} className={saved ? "fill-brand" : ""} />
          </button>
        </div>
      </article>

      {showComments && <CommentThread post={post} onClose={() => setShowComments(false)} />}
    </>
  );
}

function countComments(nodes = []) {
  return nodes.reduce((s, n) => s + 1 + countComments(n.replies || []), 0);
}
