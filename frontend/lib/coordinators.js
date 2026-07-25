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

// All four coordinators run under the Egmore MLA office. They share the
// constituency but cover different wards so the map filter and per-ward
// grievance queue actually stratify the demo data.
export const COORDINATORS = [
  {
    username: "raja",
    password: "raja123",
    name: "V. Ramkumar Raja",
    initials: "VR",
    role: "Constituency Lead",
    constituency: "16 - Egmore",
    homeWard: "58",
    avatar: "https://i.pravatar.cc/160?img=51",
    civicScore: 1560,
    reports: 112,
    resolved: 88,
    upvotes: 214,
    tenure: "4y 8m",
  },
  {
    username: "suresh",
    password: "suresh123",
    name: "Suresh Balan",
    initials: "SB",
    role: "Constituency PA",
    constituency: "16 - Egmore",
    homeWard: "77",
    avatar: "https://i.pravatar.cc/160?img=33",
    civicScore: 1180,
    reports: 92,
    resolved: 71,
    upvotes: 168,
    tenure: "2y 6m",
  },
  {
    username: "karthik",
    password: "karthik123",
    name: "Karthik Sundaram",
    initials: "KS",
    role: "Ward Coordinator",
    constituency: "16 - Egmore",
    homeWard: "78",
    avatar: "https://i.pravatar.cc/160?img=68",
    civicScore: 1240,
    reports: 87,
    resolved: 62,
    upvotes: 156,
    tenure: "3y 4m",
  },
  {
    username: "meena",
    password: "meena123",
    name: "Meena Lakshmi",
    initials: "ML",
    role: "Ward Coordinator",
    constituency: "16 - Egmore",
    homeWard: "104",
    avatar: "https://i.pravatar.cc/160?img=25",
    civicScore: 1105,
    reports: 78,
    resolved: 60,
    upvotes: 189,
    tenure: "1y 11m",
  },
];

const SESSION_KEY = "fms_coordinator_session";

/* ── Directory: seed COORDINATORS layered with admin edits from localStorage ──
 * The admin app can create, edit, disable, or reset the password of coordinators.
 * Those actions persist to a per-browser overrides bag so a demo pilot can add a
 * user, log in as them, disable them, and reload — everything sticks. In prod
 * this whole layer moves to the FastAPI backend.
 * ────────────────────────────────────────────────────────────────────────── */

const DIRECTORY_KEY = "fms_coordinator_directory_v1";

/** Read the persisted directory bag: {overrides:{[username]:partial}, extras:[coord]}. */
function readDirectoryBag() {
  const empty = { overrides: {}, extras: [] };
  if (typeof window === "undefined") return empty;
  try {
    const raw = localStorage.getItem(DIRECTORY_KEY);
    if (!raw) return empty;
    return { ...empty, ...JSON.parse(raw) };
  } catch { return empty; }
}

function writeDirectoryBag(bag) {
  if (typeof window === "undefined") return;
  localStorage.setItem(DIRECTORY_KEY, JSON.stringify(bag));
  try {
    window.dispatchEvent(new CustomEvent("fms:coordinator-directory-changed"));
  } catch { /* older browsers */ }
}

/** Every coordinator known to the app — seed + admin extras + admin overrides. */
export function listCoordinators() {
  const bag = readDirectoryBag();
  const merged = COORDINATORS.map((c) => ({
    status: "active",
    mustChangePassword: false,
    createdAt: null,
    ...c,
    ...(bag.overrides[c.username] || {}),
  }));
  const knownUsernames = new Set(merged.map((c) => c.username));
  for (const extra of bag.extras) {
    if (!knownUsernames.has(extra.username)) {
      merged.push({
        status: "active",
        mustChangePassword: false,
        ...extra,
      });
    }
  }
  return merged;
}

export function getCoordinator(username) {
  return listCoordinators().find((c) => c.username === username) || null;
}

/** Persist an override for a seeded coordinator (any subset of fields). */
export function updateCoordinator(username, patch) {
  const bag = readDirectoryBag();
  const seeded = COORDINATORS.some((c) => c.username === username);
  if (seeded) {
    bag.overrides = {
      ...bag.overrides,
      [username]: { ...(bag.overrides[username] || {}), ...patch },
    };
  } else {
    bag.extras = bag.extras.map((e) =>
      e.username === username ? { ...e, ...patch } : e
    );
  }
  writeDirectoryBag(bag);
  return getCoordinator(username);
}

/** Add a brand-new coordinator (admin-created). Rejects duplicate usernames.
 *  Also fires the record at the backend so the mobile coordinator app can
 *  authenticate this account (fire-and-forget — the web UI stays local).
 */
export function createCoordinator(coord) {
  const bag = readDirectoryBag();
  const username = (coord.username || "").trim().toLowerCase();
  if (!username) throw new Error("Username is required");
  const clash = listCoordinators().some((c) => c.username === username);
  if (clash) throw new Error("That username is already taken");
  const record = {
    status: "active",
    mustChangePassword: true,
    civicScore: 0,
    reports: 0,
    resolved: 0,
    upvotes: 0,
    tenure: "New",
    initials: initialsFrom(coord.name),
    avatar: coord.avatar || `https://i.pravatar.cc/160?u=${encodeURIComponent(username)}`,
    createdAt: new Date().toISOString(),
    ...coord,
    username,
  };
  bag.extras = [...bag.extras, record];
  writeDirectoryBag(bag);
  // Sync to backend so mobile can log in — non-blocking.
  try {
    fetch("/fms/api/admin/coordinators", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: record.name,
        username: record.username,
        password: record.password || "changeme",
        role: record.role,
        constituency: record.constituency,
        home_ward: String(record.homeWard || ""),
        must_change_password: !!record.mustChangePassword,
      }),
    }).catch(() => {});
  } catch { /* ignore */ }
  return record;
}

/** Compute 2-letter initials for the avatar fallback. */
export function initialsFrom(name = "") {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "??";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/** Reset a coordinator's password (admin action). */
export function resetPassword(username, newPassword, { mustChange = true } = {}) {
  return updateCoordinator(username, { password: newPassword, mustChangePassword: mustChange });
}

/** Toggle account status without deleting; disabled users cannot authenticate. */
export function setStatus(username, status) {
  return updateCoordinator(username, { status });
}

/** Public helper for the login form. Returns the matched active coordinator or null. */
export function authenticate(username, password) {
  const u = (username || "").trim().toLowerCase();
  const p = (password || "").trim();
  const c = listCoordinators().find((x) => x.username === u && x.password === p);
  if (!c) return null;
  if (c.status === "disabled") return null;
  return c;
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
    const c = getCoordinator(username);
    // A previously signed-in user who was later disabled is signed out.
    if (!c || c.status === "disabled") return null;
    return c;
  } catch { return null; }
}

export function clearSession() {
  if (typeof window === "undefined") return;
  localStorage.removeItem(SESSION_KEY);
}

/* ── Per-coordinator local state (verifiedIds, falsePetitionIds only) ── */

const stateKey = (username) => `fms_coord_state_${username}`;

const EMPTY_STATE = {
  verifiedIds: [],        // grievance IDs the coordinator has verified
  falsePetitionIds: [],   // grievances marked as false
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

/* ── Shared feed (posts / polls / stories) — cross-coordinator visibility ── */

const FEED_KEY = "fms_coord_shared_feed";
const EMPTY_FEED = { posts: [], polls: [], stories: [] };

export function loadFeed() {
  if (typeof window === "undefined") return { ...EMPTY_FEED };
  try {
    const raw = localStorage.getItem(FEED_KEY);
    if (!raw) return { ...EMPTY_FEED };
    const parsed = JSON.parse(raw);
    return { ...EMPTY_FEED, ...parsed };
  } catch { return { ...EMPTY_FEED }; }
}

export function saveFeed(feed) {
  if (typeof window === "undefined") return;
  localStorage.setItem(FEED_KEY, JSON.stringify(feed));
}

/* ── Shared petition actions (redirect / close / transfer / false) ── */

const ACTIONS_KEY = "fms_coord_petition_actions";

export function loadActions() {
  if (typeof window === "undefined") return [];
  try { return JSON.parse(localStorage.getItem(ACTIONS_KEY) || "[]"); }
  catch { return []; }
}

export function saveActions(actions) {
  if (typeof window === "undefined") return;
  localStorage.setItem(ACTIONS_KEY, JSON.stringify(actions));
}

/** YYYY-MM-DD in local timezone for daily-limit checks. */
export function todayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
