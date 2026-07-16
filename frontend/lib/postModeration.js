/**
 * lib/postModeration.js
 * ---------------------
 * Admin-side helpers for the post approval queue.
 *
 * Coordinator posts and polls are stamped with `status: "pending"` when they're
 * created (see CoordinatorProvider.addPost/addPoll). Admin's Post Review page
 * reads the same shared feed via loadFeed/saveFeed and transitions each item
 * between "pending" → "approved" / "rejected".
 *
 * All state lives in the same `fms_coord_shared_feed` localStorage bag —
 * decisions ripple through to the coordinator's own community view instantly.
 *
 * Legacy items (created before moderation was introduced) don't carry a
 * status; treat them as already-approved so nothing goes missing.
 */

import { loadFeed, saveFeed } from "./coordinators";

/** Change event that both the sidebar badge and the review page listen to. */
export const MODERATION_EVENT = "fms:post-moderation-changed";

function emit() {
  if (typeof window === "undefined") return;
  try { window.dispatchEvent(new CustomEvent(MODERATION_EVENT)); } catch { /* noop */ }
}

/** Return every post + poll flattened, tagged with its kind + effective status. */
export function listAll() {
  const feed = loadFeed();
  const posts = (feed.posts || []).map((p) => ({ ...p, kind: "post", status: p.status || "approved" }));
  const polls = (feed.polls || []).map((p) => ({ ...p, kind: "poll", status: p.status || "approved" }));
  // Newest submissions first — pending items should surface immediately.
  return [...posts, ...polls].sort((a, b) => {
    const at = a.submittedAt || "";
    const bt = b.submittedAt || "";
    return bt.localeCompare(at);
  });
}

export function listByStatus(status) {
  return listAll().filter((x) => x.status === status);
}

export const listPending  = () => listByStatus("pending");
export const listApproved = () => listByStatus("approved");
export const listRejected = () => listByStatus("rejected");

/** Transition a single post/poll's status. `patch` may include reason/reviewer. */
export function updateStatus(id, kind, patch) {
  const feed = loadFeed();
  const key = kind === "poll" ? "polls" : "posts";
  const items = feed[key] || [];
  const idx = items.findIndex((x) => x.id === id);
  if (idx < 0) return false;
  const updated = { ...items[idx], ...patch };
  const next = { ...feed, [key]: [...items.slice(0, idx), updated, ...items.slice(idx + 1)] };
  saveFeed(next);
  emit();
  return true;
}

/** Convenience: approve one item (records reviewer + timestamp for audit). */
export function approve(id, kind, { reviewer = "admin" } = {}) {
  return updateStatus(id, kind, {
    status: "approved",
    reviewedAt: new Date().toISOString(),
    reviewer,
    // Clear any prior reject reason if this is a re-decision.
    rejectReason: null,
  });
}

/** Convenience: reject with an optional reason (stored for audit). */
export function reject(id, kind, { reason = "", reviewer = "admin" } = {}) {
  return updateStatus(id, kind, {
    status: "rejected",
    reviewedAt: new Date().toISOString(),
    reviewer,
    rejectReason: (reason || "").trim() || null,
  });
}

/** Undo helper — used by the toast right after a decision lands. */
export function revertToPending(id, kind) {
  return updateStatus(id, kind, {
    status: "pending",
    reviewedAt: null,
    reviewer: null,
    rejectReason: null,
  });
}

/** Common rejection reason presets — one-tap on the review card. */
export const REJECT_PRESETS = [
  "Contains personal information",
  "Off-topic or unrelated",
  "Duplicate of an existing post",
  "Unverified claim or misleading",
  "Inappropriate language",
];

/* ── Demo seed ─────────────────────────────────────────────────────────────
 * Realistic MLA-office style posts covering the four use cases mentioned
 * in the product brief: engaging citizens (polls / inquiries / suggestions)
 * plus showing what's actually being done (inspection + service updates).
 * Merges non-destructively — existing coordinator submissions are kept.
 * ──────────────────────────────────────────────────────────────────────── */

function isoAgo(minutes) {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

const DEMO_POSTS = [
  // ── PENDING — the review workload
  {
    id: "p-demo-drainage", author: "raja",
    submittedAt: isoAgo(6), status: "pending",
    title: "Egmore drainage repair drive begins Monday",
    body: "Our team will start desilting work in wards 58, 77 and 78 from Monday 6am. Please plan for brief water shutoffs between 9-11am. Full route plan attached; ping me directly if your street needs priority.",
    location: "Egmore",
    audience: ["Ward Residents", "Constituency Residents"],
    hashtags: ["MondayDrive", "EgmoreServices"],
    mentions: [],
  },
  {
    id: "p-demo-eyecamp", author: "meena",
    submittedAt: isoAgo(24), status: "pending",
    title: "Free eye camp for senior citizens — Ward 104",
    body: "Saturday 10am at the community hall. Free screening and reading glasses for those above 60. Bring your Aadhaar for records. Volunteers needed, DM me if you can help register visitors.",
    location: "Ward 104, Egmore",
    audience: ["Ward Residents"],
    hashtags: ["Health", "SeniorCare"],
    mentions: [],
  },
  {
    id: "p-demo-inspection", author: "karthik",
    submittedAt: isoAgo(52), status: "pending",
    title: "Streetlight audit completed — 41 poles being replaced",
    body: "Finished the night audit along 4th Avenue and inner lanes. 41 non-functional poles identified and reported to the electrical wing. Replacement work starts Wednesday. Grateful for the residents who accompanied us during the audit.",
    location: "Ward 78, Egmore",
    audience: ["Ward Residents"],
    hashtags: ["Streetlights", "WardWatch"],
    mentions: [],
  },
  {
    id: "p-demo-scheme", author: "suresh",
    submittedAt: isoAgo(88), status: "pending",
    title: "Kalaignar Magalir Urimai Thogai — help desk open",
    body: "Getting many calls about the scheme. Help desk is now open at the PA office every weekday 10am-2pm to assist with the application. Bring ration card, Aadhaar and bank passbook. Sisters, please don't get misled by middlemen — the service is completely free.",
    location: "Egmore",
    audience: ["All Chennai", "Constituency Residents"],
    hashtags: ["MagalirThogai", "HelpDesk"],
    mentions: [],
  },
  // ── APPROVED — some history so admins can see the audit trail
  {
    id: "p-demo-metro-approved", author: "raja",
    submittedAt: isoAgo(60 * 22), status: "approved",
    reviewedAt: isoAgo(60 * 21),
    reviewer: "admin",
    title: "Metro Rail Phase-2 update — Egmore station progress",
    body: "Visited the Egmore station worksite today with the corporation engineers. Structural work is on schedule for the December opening. Requested contractors to keep noise levels down after 10pm, especially near residential blocks.",
    location: "Egmore",
    audience: ["Constituency Residents"],
    hashtags: ["MetroRail", "Egmore"],
    mentions: [],
  },
  {
    id: "p-demo-clean-approved", author: "karthik",
    submittedAt: isoAgo(60 * 30), status: "approved",
    reviewedAt: isoAgo(60 * 29),
    reviewer: "admin",
    title: "Sunday cleanliness drive — Poonamallee High Road",
    body: "Thanks to the 40+ volunteers who showed up this Sunday. We cleared over 1.2 tonnes of construction debris and litter along the stretch. Special thanks to Kumaran Traders and Sri Rama Cafe for supporting breakfast for the volunteers.",
    location: "Ward 77, Egmore",
    audience: ["Ward Residents"],
    hashtags: ["SundayDrive", "SwachhTN"],
    mentions: [],
  },
  // ── REJECTED — realistic reasons so admins see the reason UI
  {
    id: "p-demo-rejected-personal", author: "suresh",
    submittedAt: isoAgo(60 * 4), status: "rejected",
    reviewedAt: isoAgo(60 * 3),
    reviewer: "admin",
    rejectReason: "Contains personal information",
    title: "Missing person — help find Mr. Ramachandran",
    body: "Mr. Ramachandran, age 68, went missing near Gandhi Irwin bridge yesterday. Contact 98xxxxxx09 with any leads. Family is waiting.",
    location: "Egmore",
    audience: ["Ward Residents", "All Chennai"],
    hashtags: ["Missing"],
    mentions: [],
  },
];

const DEMO_POLLS = [
  {
    id: "poll-demo-meeting", author: "suresh",
    submittedAt: isoAgo(14), status: "pending",
    question: "Which time works best for the weekly ward meeting?",
    options: ["Saturday 6pm", "Sunday 10am", "Sunday 5pm"],
    location: "Egmore",
    audience: ["Ward Residents"],
  },
  {
    id: "poll-demo-priority", author: "meena",
    submittedAt: isoAgo(70), status: "pending",
    question: "What should we prioritise this quarter for Ward 104?",
    options: [
      "Storm water drain re-lining",
      "Streetlights on inner lanes",
      "Park upgrade and children's play area",
      "Youth skill training centre",
    ],
    location: "Ward 104",
    audience: ["Ward Residents", "Youth (18-35)"],
  },
  {
    id: "poll-demo-approved", author: "raja",
    submittedAt: isoAgo(60 * 40), status: "approved",
    reviewedAt: isoAgo(60 * 39),
    reviewer: "admin",
    question: "Should we hold Independence Day celebrations at Kilpauk ground?",
    options: ["Yes — plan a public event", "Yes — keep it small and school-only", "Prefer virtual"],
    location: "Kilpauk, Egmore",
    audience: ["Constituency Residents"],
  },
];

/**
 * Merge realistic demo posts into the shared feed so the review console has
 * something to work through. Never overwrites organic submissions.
 */
export function seedDemoPosts() {
  const feed = loadFeed();
  const existingPostIds = new Set((feed.posts || []).map((p) => p.id));
  const existingPollIds = new Set((feed.polls || []).map((p) => p.id));
  const newPosts = DEMO_POSTS.filter((p) => !existingPostIds.has(p.id));
  const newPolls = DEMO_POLLS.filter((p) => !existingPollIds.has(p.id));
  if (!newPosts.length && !newPolls.length) return { added: 0 };
  saveFeed({
    ...feed,
    posts: [...newPosts, ...(feed.posts || [])],
    polls: [...newPolls, ...(feed.polls || [])],
  });
  emit();
  return { added: newPosts.length + newPolls.length };
}
