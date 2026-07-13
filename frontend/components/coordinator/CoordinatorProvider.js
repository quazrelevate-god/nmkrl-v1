"use client";

/**
 * CoordinatorProvider
 * -------------------
 * Session + per-user state for the /coordinator app. Wraps the coordinator
 * routes (via app/coordinator/layout.js) and exposes:
 *   • me                   — the signed-in coordinator (or null when logged out)
 *   • state                — verifiedIds, falsePetitionIds, stories, posts, polls
 *   • verify(id)           — mark a grievance verified (moves to My Reports)
 *   • unverify(id)         — reverse
 *   • flagFalse(id)        — mark false petition
 *   • addStory(story)      — append a story (respecting the daily limit)
 *   • addPost(post)        — append a post (daily-limit gated)
 *   • addPoll(poll)        — append a poll (daily-limit gated)
 *   • canUpload{Story,Post,Poll} — booleans from daily-limit check
 *   • login / logout
 *   • composerOpen, openComposer, closeComposer — for the "+" nav button
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  authenticate, saveSession, loadSession, clearSession,
  loadState, saveState, todayKey,
} from "@/lib/coordinators";

const Ctx = createContext(null);

export function CoordinatorProvider({ children }) {
  const [me, setMe] = useState(null);
  const [state, setState] = useState(null);
  const [ready, setReady] = useState(false);
  const [composerOpen, setComposerOpen] = useState(false);

  // Hydrate from localStorage on mount.
  useEffect(() => {
    const c = loadSession();
    setMe(c);
    setState(c ? loadState(c.username) : null);
    setReady(true);
  }, []);

  const persist = useCallback((next) => {
    setState(next);
    if (me) saveState(me.username, next);
  }, [me]);

  const login = useCallback((username, password) => {
    const c = authenticate(username, password);
    if (!c) return null;
    saveSession(c);
    setMe(c);
    setState(loadState(c.username));
    return c;
  }, []);

  const logout = useCallback(() => {
    clearSession();
    setMe(null);
    setState(null);
  }, []);

  const verify = useCallback((id) => {
    if (!state || state.verifiedIds.includes(id)) return;
    persist({ ...state, verifiedIds: [...state.verifiedIds, id] });
  }, [state, persist]);

  const unverify = useCallback((id) => {
    if (!state) return;
    persist({ ...state, verifiedIds: state.verifiedIds.filter((v) => v !== id) });
  }, [state, persist]);

  const flagFalse = useCallback((id) => {
    if (!state) return;
    persist({
      ...state,
      verifiedIds: state.verifiedIds.filter((v) => v !== id),
      falsePetitionIds: state.falsePetitionIds.includes(id)
        ? state.falsePetitionIds
        : [...state.falsePetitionIds, id],
    });
  }, [state, persist]);

  // Daily-limit checks: at most 1 story, 1 post, 1 poll per calendar day per user.
  const t = todayKey();
  const canUploadStory = useMemo(
    () => !state?.stories?.some((s) => s.date === t), [state, t]);
  const canUploadPost = useMemo(
    () => !state?.posts?.some((p) => p.date === t), [state, t]);
  const canUploadPoll = useMemo(
    () => !state?.polls?.some((p) => p.date === t), [state, t]);

  const addStory = useCallback((story) => {
    if (!state || !canUploadStory) return false;
    persist({ ...state, stories: [{ id: `sty-${Date.now()}`, date: t, ...story }, ...state.stories] });
    return true;
  }, [state, persist, canUploadStory, t]);

  const addPost = useCallback((post) => {
    if (!state || !canUploadPost) return false;
    persist({ ...state, posts: [{ id: `p-${Date.now()}`, date: t, ...post }, ...state.posts] });
    return true;
  }, [state, persist, canUploadPost, t]);

  const addPoll = useCallback((poll) => {
    if (!state || !canUploadPoll) return false;
    persist({ ...state, polls: [{ id: `poll-${Date.now()}`, date: t, ...poll }, ...state.polls] });
    return true;
  }, [state, persist, canUploadPoll, t]);

  const value = useMemo(() => ({
    me, state, ready, login, logout,
    verify, unverify, flagFalse,
    addStory, addPost, addPoll,
    canUploadStory, canUploadPost, canUploadPoll,
    composerOpen, openComposer: () => setComposerOpen(true), closeComposer: () => setComposerOpen(false),
  }), [
    me, state, ready, login, logout, verify, unverify, flagFalse,
    addStory, addPost, addPoll, canUploadStory, canUploadPost, canUploadPoll, composerOpen,
  ]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useCoordinator() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useCoordinator must be used within CoordinatorProvider");
  return v;
}
