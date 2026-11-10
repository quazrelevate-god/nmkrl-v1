/**
 * lib/storyModeration.js
 * ----------------------
 * Ward stories in the admin Post Review queue.
 *
 * Posts and polls live in localStorage (see postModeration.js) and were only
 * ever a demo loop. Stories are real: a coordinator posts one from the mobile
 * app, it lands PENDING in the backend, and it reaches citizens only once this
 * console approves it. So this module talks to the API rather than to a
 * browser bag.
 *
 * It deliberately returns items in the SAME shape the review page already
 * understands — `{ id, kind, status, author, title, body, media, submittedAt }`
 * with a lowercase status — so stories slot in beside posts and polls instead
 * of needing a second page. Translating at the edge keeps the mapping in one
 * readable place:
 *
 *     backend            page
 *     PENDING / APPROVED / REJECTED  ->  pending / approved / rejected
 *     caption                        ->  body
 *     image_url                      ->  media
 *     created_at                     ->  submittedAt
 *
 * Undo is asymmetric and that is on purpose. A rejected story was never
 * public, so it can go back to the queue; an approved one may already be on a
 * ward's rail in front of citizens, and the backend refuses to un-publish it.
 * See [canRevert].
 */

import { API_BASE, mediaUrl } from "./api";
import { adminHeaders } from "./adminAuth";

/** Change event, shared with postModeration so one badge listens to both. */
export const STORY_MODERATION_EVENT = "fms:post-moderation-changed";

function emit() {
  if (typeof window === "undefined") return;
  try {
    window.dispatchEvent(new CustomEvent(STORY_MODERATION_EVENT));
  } catch {
    /* noop */
  }
}

/** One backend row as the review page's item shape. */
function toItem(s) {
  return {
    id: s.id,
    kind: "story",
    status: String(s.status || "PENDING").toLowerCase(),
    author: s.author_name || s.author || "",
    authorUsername: s.author || "",
    title: s.title || "",
    body: s.caption || "",
    media: mediaUrl(s.image_url),
    ward: s.ward,
    submittedAt: s.created_at || "",
    expiresAt: s.expires_at || "",
    reviewedBy: s.reviewed_by || "",
    reviewedAt: s.reviewed_at || "",
    reviewNote: s.review_note || "",
  };
}

async function call(path, options = {}) {
  const res = await fetch(`${API_BASE}/api/admin/stories${path}`, {
    ...options,
    headers: adminHeaders(options.headers || {}),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `Request failed (${res.status})`);
  }
  return res.json();
}

/**
 * Every story this MLA office may review, in all three states.
 *
 * The backend scopes to the office's own wards from the signed token, so
 * there is nothing to pass and nothing a crafted request could widen.
 */
export async function listStories() {
  const data = await call("?status=ALL");
  return (data.stories || []).map(toItem);
}

/** How many are waiting — for the sidebar badge, without fetching the queue. */
export async function pendingCount() {
  const data = await call("");
  return data.pending || 0;
}

export async function approveStory(id, { note = "" } = {}) {
  const body = new FormData();
  body.append("note", note);
  const out = await call(`/${id}/approve`, { method: "POST", body });
  emit();
  return toItem(out);
}

export async function rejectStory(id, { reason = "" } = {}) {
  const body = new FormData();
  body.append("note", reason);
  const out = await call(`/${id}/reject`, { method: "POST", body });
  emit();
  return toItem(out);
}

/** Put a REJECTED story back in the queue. Approved ones cannot come back. */
export async function revertStory(id) {
  const out = await call(`/${id}/revert`, { method: "POST" });
  emit();
  return toItem(out);
}

/**
 * Whether Undo should be offered for this item.
 *
 * Rejections are reversible because nobody saw them. An approval is not: the
 * story is on the ward's rail, and making it vanish for people who have
 * already read it is a different act from un-deciding — that is what Delete
 * is for, and it leaves a trace.
 */
export function canRevert(item) {
  return item?.kind === "story" && item?.status === "rejected";
}
