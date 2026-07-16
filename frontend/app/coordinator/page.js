"use client";

/**
 * Coordinator home — mirrors the citizen community feed with the coordinator's
 * own published posts/polls prepended and the profile-morph header swapped for
 * CoordinatorHeader (their real identity + a "+" story-upload chip).
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import CoordinatorShell from "@/components/coordinator/CoordinatorShell";
import CoordinatorHeader from "@/components/coordinator/CoordinatorHeader";
import StoryViewer from "@/components/community/StoryViewer";
import PostCard from "@/components/community/PostCard";
import TodaysPulse from "@/components/community/TodaysPulse";
import StoryUploadModal from "@/components/coordinator/StoryUploadModal";
import { useCoordinator } from "@/components/coordinator/CoordinatorProvider";
import { COORDINATORS } from "@/lib/coordinators";
import { FEED } from "@/lib/communityData";

const TRAVEL = 130;
const SNAP_DELAY = 160;

export default function CoordinatorHomePage() {
  const { me, feed, addStory, canUploadStory } = useCoordinator();
  const [progress, setProgress] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [activeStory, setActiveStory] = useState(null);
  const [padTop, setPadTop] = useState(170);
  const [storyOpen, setStoryOpen] = useState(false);
  const [constituency, setConstituency] = useState(me?.constituency || "20 - Anna Nagar");

  const scrollRef = useRef(null);
  const pRef = useRef(0);
  const drag = useRef(null);
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

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const onTouchStart = (e) => { drag.current = { y: e.touches[0].clientY, start: pRef.current }; };
    const onTouchMove = (e) => {
      if (!drag.current) return;
      const atTop = el.scrollTop <= 0;
      const dy = e.touches[0].clientY - drag.current.y;
      if (pRef.current > 0 || (atTop && dy > 0)) {
        const np = Math.max(0, Math.min(1, drag.current.start + dy / TRAVEL));
        setDragging(true);
        setP(np);
        if (np > 0) e.preventDefault();
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

  // Every coordinator's published posts/polls from the shared feed, mapped
  // into PostCard-shaped items and prepended to the curated FEED.
  const coordFeedItems = useMemo(() => {
    if (!feed) return [];
    const authorMap = Object.fromEntries(COORDINATORS.map((c) => [c.username, c]));

    // Hide rejected submissions from the feed entirely (only the author's own
    // admin queue view reveals rejections). Pending items stay visible so
    // coordinators can watch their own posts move through review in real time.
    const visiblePosts = (feed.posts || []).filter((p) => p.status !== "rejected");
    const visiblePolls = (feed.polls || []).filter((p) => p.status !== "rejected");

    const posts = visiblePosts.map((p) => {
      const a = authorMap[p.author] || { name: p.author, username: p.author, avatar: "" };
      return {
        id: p.id,
        type: p.mediaKind === "video" ? "video" : p.media ? "image" : "text",
        author: a.name,
        handle: `@${a.username}`,
        verified: true,
        avatar: a.avatar,
        area: p.location || a.constituency?.replace(/^\d+\s*-\s*/, "") || "Chennai",
        time: "Recently",
        status: "Official Update",
        title: p.title || "Coordinator update",
        body: p.body || "",
        media: p.media && p.mediaKind !== "video" ? [p.media] : undefined,
        poster: p.mediaKind === "video" ? p.media : undefined,
        video: p.mediaKind === "video" ? p.media : undefined,
        tag: "Coordinator",
        location: p.location,
        likes: 0, shares: 0, comments: [],
        mentions: p.mentions,
        hashtags: p.hashtags,
        audience: p.audience,
        moderationStatus: p.status || "approved",
      };
    });

    const polls = visiblePolls.map((p) => {
      const a = authorMap[p.author] || { name: p.author, username: p.author, avatar: "" };
      return {
        id: p.id,
        type: "poll",
        author: a.name,
        handle: `@${a.username}`,
        verified: true,
        avatar: a.avatar,
        area: p.location || a.constituency?.replace(/^\d+\s*-\s*/, "") || "Chennai",
        time: "Recently",
        question: p.question,
        body: p.body || "",
        options: p.options.map((o) => ({ label: o, votes: 0 })),
        totalVotes: 0,
        daysLeft: 7, likes: 0, shares: 0, comments: [],
        audience: p.audience,
        moderationStatus: p.status || "approved",
      };
    });

    return [...posts, ...polls];
  }, [feed]);

  const combinedFeed = useMemo(() => [...coordFeedItems, ...FEED], [coordFeedItems]);

  function handleAddStory() {
    if (canUploadStory) setStoryOpen(true);
  }

  function publishStory(story) {
    addStory(story);
  }

  return (
    <CoordinatorShell fullBleed>
      <CoordinatorHeader
        progress={progress}
        dragging={dragging}
        onOpenStory={setActiveStory}
        onSetProgress={(v) => { setDragging(false); setP(v); }}
        onCompact={setPadTop}
        onAddStory={handleAddStory}
        constituency={constituency}
        onConstituency={setConstituency}
      />

      <div ref={scrollRef}
        className="no-scrollbar absolute inset-0 overflow-y-auto overscroll-contain"
        style={{ paddingTop: padTop + 8, paddingBottom: 116 }}>
        {/* Today's Pulse — MLA social panel + Tamil news carousel */}
        <TodaysPulse constituency={constituency} />

        <div className="mt-3 space-y-3 px-4">
          {combinedFeed.map((post, i) => (
            <PostCard key={post.id} post={post} index={i} />
          ))}
          <p className="py-4 text-center text-xs text-slate-400">You're all caught up · {combinedFeed.length} posts</p>
        </div>
      </div>

      {/* Progress-driven blur+dim (like citizen home) */}
      <div className="absolute inset-0 z-20"
        style={{
          background: `rgba(15,23,42,${(progress * 0.4).toFixed(3)})`,
          backdropFilter: progress > 0.02 ? `blur(${(progress * 5).toFixed(2)}px)` : "none",
          WebkitBackdropFilter: progress > 0.02 ? `blur(${(progress * 5).toFixed(2)}px)` : "none",
          pointerEvents: progress > 0.05 ? "auto" : "none",
          transition: dragging ? "none" : "background .45s cubic-bezier(.22,1,.36,1), backdrop-filter .45s cubic-bezier(.22,1,.36,1)",
        }}
        onClick={() => { setDragging(false); setP(0); }} />

      {activeStory && <StoryViewer story={activeStory} onClose={() => setActiveStory(null)} />}
      <StoryUploadModal open={storyOpen} onClose={() => setStoryOpen(false)} onPublish={publishStory} />
    </CoordinatorShell>
  );
}
