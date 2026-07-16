"use client";

/**
 * CoordinatorProvider
 * -------------------
 * Session + shared-feed + petition-actions store for the /coordinator app.
 *
 * • me / state           per-user (session, verifiedIds, falsePetitionIds)
 * • feed                 SHARED across coordinators (posts, polls, stories,
 *                        each tagged with the author's username)
 * • actions              SHARED petition actions (redirect / close / transfer
 *                        / false) — surfaced by admin panel
 * • daily limits         derived from the shared feed matching this user
 * • addPost/Poll/Story   append to the shared feed
 * • addAction            append a petition action
 * • hasActioned / actionFor  quick lookups from the actions store
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  authenticate, saveSession, loadSession, clearSession,
  loadState, saveState, todayKey,
  loadFeed, saveFeed, loadActions, saveActions,
} from "@/lib/coordinators";

const Ctx = createContext(null);

export function CoordinatorProvider({ children }) {
  const [me, setMe] = useState(null);
  const [state, setState] = useState(null);
  const [feed, setFeed] = useState({ posts: [], polls: [], stories: [] });
  const [actions, setActions] = useState([]);
  const [ready, setReady] = useState(false);
  const [composerOpen, setComposerOpen] = useState(false);

  // Hydrate.
  useEffect(() => {
    const c = loadSession();
    setMe(c);
    setState(c ? loadState(c.username) : null);
    setFeed(loadFeed());
    setActions(loadActions());
    setReady(true);
  }, []);

  const persistState = useCallback((next) => {
    setState(next);
    if (me) saveState(me.username, next);
  }, [me]);

  const persistFeed = useCallback((next) => {
    setFeed(next);
    saveFeed(next);
  }, []);

  const persistActions = useCallback((next) => {
    setActions(next);
    saveActions(next);
  }, []);

  const login = useCallback((username, password) => {
    const c = authenticate(username, password);
    if (!c) return null;
    saveSession(c);
    setMe(c);
    setState(loadState(c.username));
    setFeed(loadFeed());
    setActions(loadActions());
    return c;
  }, []);

  const logout = useCallback(() => {
    clearSession();
    setMe(null);
    setState(null);
  }, []);

  const verify = useCallback((id) => {
    if (!state || state.verifiedIds.includes(id)) return;
    persistState({ ...state, verifiedIds: [...state.verifiedIds, id] });
  }, [state, persistState]);

  const unverify = useCallback((id) => {
    if (!state) return;
    persistState({ ...state, verifiedIds: state.verifiedIds.filter((v) => v !== id) });
  }, [state, persistState]);

  const flagFalse = useCallback((id) => {
    if (!state) return;
    persistState({
      ...state,
      verifiedIds: state.verifiedIds.filter((v) => v !== id),
      falsePetitionIds: state.falsePetitionIds.includes(id)
        ? state.falsePetitionIds
        : [...state.falsePetitionIds, id],
    });
  }, [state, persistState]);

  // Daily-limit checks: shared feed filtered to THIS coordinator + today.
  const t = todayKey();
  const canUploadStory = useMemo(
    () => !me || !feed.stories.some((s) => s.author === me.username && s.date === t),
    [feed, me, t]);
  const canUploadPost = useMemo(
    () => !me || !feed.posts.some((p) => p.author === me.username && p.date === t),
    [feed, me, t]);
  const canUploadPoll = useMemo(
    () => !me || !feed.polls.some((p) => p.author === me.username && p.date === t),
    [feed, me, t]);

  const addStory = useCallback((story) => {
    if (!me || !canUploadStory) return false;
    persistFeed({
      ...feed,
      stories: [{ id: `sty-${Date.now()}`, author: me.username, date: t, ...story }, ...feed.stories],
    });
    return true;
  }, [me, canUploadStory, feed, persistFeed, t]);

  // New posts/polls land in the moderation queue as "pending" and only appear
  // in the citizen-facing feed after the admin approves them. Coordinators
  // still see their own submissions on their community view with a status
  // pill so they know where each one stands.
  const addPost = useCallback((post) => {
    if (!me || !canUploadPost) return false;
    const now = new Date().toISOString();
    persistFeed({
      ...feed,
      posts: [{
        id: `p-${Date.now()}`,
        author: me.username,
        date: t,
        submittedAt: now,
        status: "pending",
        ...post,
      }, ...feed.posts],
    });
    return true;
  }, [me, canUploadPost, feed, persistFeed, t]);

  const addPoll = useCallback((poll) => {
    if (!me || !canUploadPoll) return false;
    const now = new Date().toISOString();
    persistFeed({
      ...feed,
      polls: [{
        id: `poll-${Date.now()}`,
        author: me.username,
        date: t,
        submittedAt: now,
        status: "pending",
        ...poll,
      }, ...feed.polls],
    });
    return true;
  }, [me, canUploadPoll, feed, persistFeed, t]);

  // Petition actions.
  const addAction = useCallback((action) => {
    if (!me) return false;
    const entry = {
      id: `act-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      coordinator: me.username,
      coordinatorName: me.name,
      constituency: me.constituency,
      timestamp: new Date().toISOString(),
      ...action,
    };
    persistActions([entry, ...actions]);
    return entry;
  }, [me, actions, persistActions]);

  const hasActioned = useCallback((issueId) => actions.some((a) => a.issueId === issueId), [actions]);
  const actionFor = useCallback((issueId) => actions.find((a) => a.issueId === issueId) || null, [actions]);

  const value = useMemo(() => ({
    me, state, ready, feed, actions,
    login, logout,
    verify, unverify, flagFalse,
    addStory, addPost, addPoll, addAction,
    hasActioned, actionFor,
    canUploadStory, canUploadPost, canUploadPoll,
    composerOpen, openComposer: () => setComposerOpen(true), closeComposer: () => setComposerOpen(false),
  }), [
    me, state, ready, feed, actions,
    login, logout, verify, unverify, flagFalse,
    addStory, addPost, addPoll, addAction, hasActioned, actionFor,
    canUploadStory, canUploadPost, canUploadPoll, composerOpen,
  ]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useCoordinator() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useCoordinator must be used within CoordinatorProvider");
  return v;
}
