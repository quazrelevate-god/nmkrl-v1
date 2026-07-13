/**
 * lib/coordinators.js
 * -------------------
 * Seed table of 4 constituency coordinators for the /coordinator staff app.
 * Simple username/password auth (PoC only). Each coordinator has a distinct
 * profile that drives the home page, the assigned constituency/ward, and the
 * per-user local state (verified grievances, daily limits).
 *
 * NOTE: This is illustrative PoC auth — never use plain-text passwords in prod.
 */

export const COORDINATORS = [
  {
    username: "raja",
    password: "raja123",
    name: "V. Ramkumar Raja",
    initials: "VR",
    role: "Ward Coordinator",
    constituency: "20 - Anna Nagar",
    homeWard: "103",
    avatar: "https://i.pravatar.cc/160?img=12",
    civicScore: 1240,
    reports: 87,
    resolved: 62,
    upvotes: 156,
    tenure: "3y 4m",
  },
  {
    username: "divya",
    password: "divya123",
    name: "Divya Nathan",
    initials: "DN",
    role: "Constituency PA",
    constituency: "18 - Chepauk-Thiruvallikeni",
    homeWard: "115",
    avatar: "https://i.pravatar.cc/160?img=45",
    civicScore: 980,
    reports: 64,
    resolved: 51,
    upvotes: 132,
    tenure: "2y 1m",
  },
  {
    username: "karthik",
    password: "karthik123",
    name: "Karthik Sundaram",
    initials: "KS",
    role: "Ward Coordinator",
    constituency: "23 - Thiyagarayanagar",
    homeWard: "133",
    avatar: "https://i.pravatar.cc/160?img=15",
    civicScore: 1560,
    reports: 112,
    resolved: 88,
    upvotes: 214,
    tenure: "4y 8m",
  },
  {
    username: "meena",
    password: "meena123",
    name: "Meena Lakshmi",
    initials: "ML",
    role: "Constituency PA",
    constituency: "24 - Mylapore",
    homeWard: "173",
    avatar: "https://i.pravatar.cc/160?img=32",
    civicScore: 1105,
    reports: 78,
    resolved: 60,
    upvotes: 189,
    tenure: "1y 11m",
  },
];

const SESSION_KEY = "fms_coordinator_session";

/** Public helper for the login form. Returns the matched coordinator or null. */
export function authenticate(username, password) {
  const u = (username || "").trim().toLowerCase();
  const p = (password || "").trim();
  return COORDINATORS.find((c) => c.username === u && c.password === p) || null;
}

/** Persist / read the signed-in coordinator (localStorage). */
export function saveSession(coordinator) {
  if (typeof window === "undefined") return;
  localStorage.setItem(SESSION_KEY, JSON.stringify({ username: coordinator.username }));
}

export function loadSession() {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const { username } = JSON.parse(raw);
    return COORDINATORS.find((c) => c.username === username) || null;
  } catch { return null; }
}

export function clearSession() {
  if (typeof window === "undefined") return;
  localStorage.removeItem(SESSION_KEY);
}

/* ── Per-coordinator local state (verified issues + daily limits + stories) ── */

const stateKey = (username) => `fms_coord_state_${username}`;

const EMPTY_STATE = {
  verifiedIds: [],        // grievance IDs the coordinator has verified
  falsePetitionIds: [],   // grievances marked as false
  stories: [],            // uploaded stories (each: {id, image, caption, date})
  posts: [],              // published posts (each: {id, kind, ...})
  polls: [],              // published polls
};

export function loadState(username) {
  if (typeof window === "undefined" || !username) return { ...EMPTY_STATE };
  try {
    const raw = localStorage.getItem(stateKey(username));
    if (!raw) return { ...EMPTY_STATE };
    return { ...EMPTY_STATE, ...JSON.parse(raw) };
  } catch { return { ...EMPTY_STATE }; }
}

export function saveState(username, state) {
  if (typeof window === "undefined" || !username) return;
  localStorage.setItem(stateKey(username), JSON.stringify(state));
}

/** YYYY-MM-DD in local timezone for daily-limit checks. */
export function todayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
