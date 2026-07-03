"use client";

/**
 * StoryViewer
 * -----------
 * Full-screen Instagram-style story viewer. Auto-advancing progress bars,
 * tap left/right to navigate, and inline Like + Comment on each slide.
 */

import { useEffect, useRef, useState } from "react";
import { X, Heart, Send } from "lucide-react";

const SLIDE_MS = 5000;

export default function StoryViewer({ story, onClose }) {
  const slides = story?.slides || [];
  const [idx, setIdx] = useState(0);
  const [liked, setLiked] = useState({});
  const [comments, setComments] = useState({});
  const [draft, setDraft] = useState("");
  const [paused, setPaused] = useState(false);
  const timer = useRef(null);

  // Close once we advance past the last slide (side effect, not in render).
  useEffect(() => {
    if (idx >= slides.length && slides.length) onClose?.();
  }, [idx, slides.length, onClose]);

  useEffect(() => {
    if (paused || idx >= slides.length) return;
    timer.current = setTimeout(() => setIdx(i => i + 1), SLIDE_MS);
    return () => clearTimeout(timer.current);
  }, [idx, paused, slides.length]);

  if (!story || idx >= slides.length) return null;
  const slide = slides[idx];

  function prev() { setIdx(i => Math.max(0, i - 1)); }
  function next() { setIdx(i => i + 1); }

  function addComment() {
    const t = draft.trim();
    if (!t) return;
    setComments(c => ({ ...c, [idx]: [...(c[idx] || []), t] }));
    setDraft("");
  }

  return (
    <div className="absolute inset-0 z-[800] flex flex-col bg-black">
      {/* Progress bars */}
      <div className="flex gap-1 px-3 pt-3">
        {slides.map((_, i) => (
          <div key={i} className="h-0.5 flex-1 overflow-hidden rounded-full bg-white/30">
            <div
              className={i < idx ? "h-full w-full bg-white" : i === idx ? "h-full bg-white animate-story-fill" : "h-full w-0 bg-white"}
              style={i === idx ? { animationDuration: `${SLIDE_MS}ms`, animationPlayState: paused ? "paused" : "running" } : undefined}
            />
          </div>
        ))}
      </div>

      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 text-white">
        <div className="flex items-center gap-2">
          <div className={`rounded-full bg-gradient-to-br ${story.ring} p-[2px]`}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={slide.image} alt="" className="h-8 w-8 rounded-full border border-black object-cover" />
          </div>
          <span className="text-sm font-semibold">{story.label}</span>
        </div>
        <button onClick={onClose} className="rounded-full p-1 hover:bg-white/10"><X size={22} /></button>
      </div>

      {/* Media */}
      <div className="relative flex-1" onPointerDown={() => setPaused(true)} onPointerUp={() => setPaused(false)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={slide.image} alt="" className="absolute inset-0 h-full w-full object-cover" />
        {/* Tap zones */}
        <button className="absolute left-0 top-0 h-full w-1/3" onClick={prev} aria-label="Previous" />
        <button className="absolute right-0 top-0 h-full w-1/3" onClick={next} aria-label="Next" />

        {/* Caption */}
        <div className="absolute inset-x-0 bottom-24 px-4">
          <p className="rounded-2xl bg-black/35 px-3 py-2 text-sm font-medium text-white backdrop-blur-sm">{slide.caption}</p>
          {(comments[idx] || []).map((c, i) => (
            <p key={i} className="mt-1 w-fit rounded-full bg-white/90 px-3 py-1 text-xs font-medium text-slate-800">{c}</p>
          ))}
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2 px-3 pb-5 pt-2">
        <div className="flex flex-1 items-center rounded-full border border-white/30 bg-white/10 px-3">
          <input
            value={draft}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => e.key === "Enter" && addComment()}
            onFocus={() => setPaused(true)}
            onBlur={() => setPaused(false)}
            placeholder="Reply to this story…"
            className="flex-1 bg-transparent py-2.5 text-sm text-white placeholder:text-white/60 outline-none"
          />
          <button onClick={addComment} className="text-white/80"><Send size={16} /></button>
        </div>
        <button
          onClick={() => setLiked(l => ({ ...l, [idx]: !l[idx] }))}
          className="flex h-11 w-11 items-center justify-center rounded-full bg-white/10"
        >
          <Heart size={22} className={liked[idx] ? "fill-red-500 text-red-500" : "text-white"} />
        </button>
      </div>
    </div>
  );
}
