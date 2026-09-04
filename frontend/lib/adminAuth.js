/**
 * lib/adminAuth.js
 * ----------------
 * Admin console session: one signed token from the backend, kept in this
 * browser, sent on every admin request.
 *
 * The console used to be reachable by anyone who knew the URL — including the
 * pages that create coordinator accounts and reset their passwords. The token
 * is minted by POST /api/admin/auth/login and verified server-side on every
 * /api/admin/* call, so removing it from storage does not get anyone past the
 * lock; it only signs this browser out.
 */

import { API_BASE } from "@/lib/api";

const TOKEN_KEY = "nk_admin_token";
const USER_KEY = "nk_admin_user";

export function getAdminToken() {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function getAdminUser() {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(USER_KEY);
  } catch {
    return null;
  }
}

/** Header bag for an admin request. Empty when signed out, so the request
 *  fails with 401 rather than silently looking like a different user. */
export function adminHeaders(extra = {}) {
  const token = getAdminToken();
  return token ? { ...extra, "X-Admin-Token": token } : { ...extra };
}

export async function adminLogin(username, password) {
  const body = new FormData();
  body.append("username", username);
  body.append("password", password);
  const res = await fetch(`${API_BASE}/api/admin/auth/login`, { method: "POST", body });
  if (!res.ok) {
    const b = await res.json().catch(() => ({}));
    throw new Error(b.detail || "Sign-in failed. Check the username and password.");
  }
  const data = await res.json();
  try {
    localStorage.setItem(TOKEN_KEY, data.token);
    localStorage.setItem(USER_KEY, data.username);
  } catch {
    /* private mode — the session lasts this page only */
  }
  return data;
}

export function adminLogout() {
  try {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  } catch {
    /* nothing to clear */
  }
}

/** Ask the server whether the stored token is still good. A token that has
 *  expired, or was signed by a previous boot's secret, fails here. */
export async function verifyAdminToken() {
  const token = getAdminToken();
  if (!token) return false;
  try {
    const res = await fetch(`${API_BASE}/api/admin/auth/me`, {
      headers: { "X-Admin-Token": token },
      cache: "no-store",
    });
    if (res.status === 401) {
      adminLogout();
      return false;
    }
    return res.ok;
  } catch {
    // Network trouble is not proof of a bad token — keep the session and let
    // the next real request decide, rather than dumping the operator out.
    return true;
  }
}
