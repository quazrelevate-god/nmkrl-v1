/**
 * lib/user.js
 * -----------
 * The PoC has no auth. We generate a stable per-browser user id and keep it in
 * localStorage so "My History" and upvote-dedup work consistently per device.
 */

const KEY = "fms_user_id";

export function getUserId() {
  if (typeof window === "undefined") return "demo-user";
  let id = window.localStorage.getItem(KEY);
  if (!id) {
    id =
      "user-" +
      Math.random().toString(36).slice(2, 8) +
      Date.now().toString(36).slice(-4);
    window.localStorage.setItem(KEY, id);
  }
  return id;
}
