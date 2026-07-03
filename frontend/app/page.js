"use client";

/**
 * Community — default landing.
 * Fullscreen feed that scrolls edge-to-edge *behind* a fixed glass header and
 * the glass pill nav. The profile↔stories header morphs continuously, driven in
 * real time by the user's drag / wheel delta and snapped with spring easing.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import MobileShell from "@/components/MobileShell";
import CommunityHeader from "@/components/community/CommunityHeader";
import StoryViewer from "@/components/community/StoryViewer";
import PostCard from "@/components/community/PostCard";
import { FEED } from "@/lib/communityData";

const TRAVEL = 130;          // px of drag / wheel for a full 0→1 morph
const SNAP_DELAY = 160;      // ms of wheel inactivity before snapping

export default function CommunityScreen() {
  const [progress, setProgress] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [activeStory, setActiveStory] = useState(null);
  const [padTop, setPadTop] = useState(170);

  const scrollRef = useRef(null);
  const pRef = useRef(0);         // live progress for native listeners
  const drag = useRef(null);      // touch drag session
  const snapTimer = useRef(null);

  const setP = useCallback((v) => {
    const c = Math.max(0, Math.min(1, v));
    pRef.current = c;
    setProgress(c);
  }, []);

  const snap = useCallback(() => {
    setDragging(false);
    setP(pRef.current >= 0.5 ? 1 : 0);
  }, [setP]);

  // Real-time, gesture-responsive morph via native (non-passive) listeners so
  // we can preventDefault the scroll while the header is being pulled open.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    const onTouchStart = (e) => {
      drag.current = { y: e.touches[0].clientY, start: pRef.current };
    };
    const onTouchMove = (e) => {
      if (!drag.current) return;
      const atTop = el.scrollTop <= 0;
      const dy = e.touches[0].clientY - drag.current.y;
      if (pRef.current > 0 || (atTop && dy > 0)) {
        const np = Math.max(0, Math.min(1, drag.current.start + dy / TRAVEL));
        setDragging(true);
        setP(np);
        if (np > 0) e.preventDefault(); // hold the scroll while morphing
      }
    };
    const onTouchEnd = () => { drag.current = null; snap(); };

    const onWheel = (e) => {
      const atTop = el.scrollTop <= 0;
      const opening = e.deltaY < 0 && atTop && pRef.current < 1;
      const closing = e.deltaY > 0 && pRef.current > 0 && atTop;
      if (opening || closing) {
        e.preventDefault();
        setDragging(true);
        setP(pRef.current - e.deltaY / TRAVEL);
        clearTimeout(snapTimer.current);
        snapTimer.current = setTimeout(snap, SNAP_DELAY);
      }
    };

    el.addEventListener("touchstart", onTouchStart, { passive: true });
    el.addEventListener("touchmove", onTouchMove, { passive: false });
    el.addEventListener("touchend", onTouchEnd, { passive: true });
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => {
      el.removeEventListener("touchstart", onTouchStart);
      el.removeEventListener("touchmove", onTouchMove);
      el.removeEventListener("touchend", onTouchEnd);
      el.removeEventListener("wheel", onWheel);
      clearTimeout(snapTimer.current);
    };
  }, [setP, snap]);

  return (
    <MobileShell fullBleed>
      <CommunityHeader
        progress={progress}
        dragging={dragging}
        onOpenStory={setActiveStory}
        onSetProgress={(v) => { setDragging(false); setP(v); }}
        onCompact={setPadTop}
      />

      <div
        ref={scrollRef}
        className="no-scrollbar absolute inset-0 overflow-y-auto overscroll-contain"
        style={{ paddingTop: padTop + 8, paddingBottom: 116 }}
      >
        <div className="space-y-3 px-4">
          {FEED.map((post, i) => (
            <PostCard key={post.id} post={post} index={i} />
          ))}
          <p className="py-4 text-center text-xs text-slate-400">You're all caught up · {FEED.length} posts</p>
        </div>
      </div>

      {activeStory && <StoryViewer story={activeStory} onClose={() => setActiveStory(null)} />}
    </MobileShell>
  );
}
