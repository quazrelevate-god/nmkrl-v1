/**
 * lib/dailyLimit.js
 * -----------------
 * Tiny localStorage-backed per-day quota for the PoC (fair-use limits like
 * "1 grievance / day" and "5 supports / day"). Resets automatically at
 * midnight (keyed on the local date string).
 */

function todayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

/** Current state: { used, remaining, max }. Safe during SSR. */
export function dailyState(key, max) {
  if (typeof window === "undefined") return { used: 0, remaining: max, max };
  try {
    const raw = JSON.parse(localStorage.getItem(key) || "{}");
    const used = raw.date === todayKey() ? raw.used || 0 : 0;
    return { used, remaining: Math.max(0, max - used), max };
  } catch {
    return { used: 0, remaining: max, max };
  }
}

/** Consume one unit and return the new state (no-op past the limit). */
export function consumeDaily(key, max) {
  const s = dailyState(key, max);
  if (s.remaining <= 0) return s;
  const used = s.used + 1;
  try { localStorage.setItem(key, JSON.stringify({ date: todayKey(), used })); } catch {}
  return { used, remaining: Math.max(0, max - used), max };
}

export const GRIEVANCE_LIMIT_KEY = "nk_grievance_quota";
export const SUPPORT_LIMIT_KEY = "nk_support_quota";
