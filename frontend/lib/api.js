/**
 * lib/api.js
 * ----------
 * Thin, typed-ish wrapper around the FastAPI backend. Centralises the base URL,
 * error handling, and the multipart/form-data plumbing so screens stay clean.
 *
 * The integration boundary: every function here maps 1:1 to a backend route in
 * routers/issues.py or routers/admin.py.
 */

// /fms prefix is proxied by Next.js rewrites → FastAPI. NEXT_PUBLIC_API_BASE
// can override to call FastAPI directly. A scheme-less value (e.g. a bare
// Railway domain) is upgraded to https:// so it resolves as an absolute URL
// instead of a same-origin path.
function _resolveApiBase() {
  const b = (process.env.NEXT_PUBLIC_API_BASE || "").trim();
  if (!b) return "/fms";
  if (b.startsWith("/") || /^https?:\/\//i.test(b)) return b;
  return `https://${b}`;
}
export const API_BASE = _resolveApiBase();

// Admin requests carry a signed token; see lib/adminAuth.js. Imported lazily
// through a function so the two modules can reference each other safely.
import { adminHeaders } from "@/lib/adminAuth";

/** Resolve a stored media path (e.g. "/uploads/..") to an absolute URL.
 *
 * Paths starting with "/community/" are static frontend assets bundled with
 * the app (real civic photos) — they resolve against the current origin, not
 * proxied through /fms/uploads/.
 */
export function mediaUrl(path) {
  if (!path) return null;
  if (path.startsWith("http")) return path;
  if (path.startsWith("/community/")) return path;
  return `${API_BASE}${path}`;
}

/** Internal: parse JSON and throw a useful Error on non-2xx. */
async function handle(res) {
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* non-JSON response */
  }
  if (!res.ok) {
    const detail = body?.detail || res.statusText || "Request failed";
    const err = new Error(detail);
    err.status = res.status;
    err.body = body;
    throw err;
  }
  return body;
}

/** Request a one-time code for a mobile number. Used by the web account-
 *  deletion page; in dev mode the response carries the code as `dev_otp`. */
export async function requestOtp(phone) {
  const fd = new FormData();
  fd.append("phone", phone);
  const res = await fetch(`${API_BASE}/api/auth/request-otp`, { method: "POST", body: fd });
  return handle(res);
}

/** Delete an account from the web, proven by a fresh SMS code. Removes the
 *  person's personal data and anonymises the grievances they filed. */
export async function deleteAccountWithCode(phone, otp) {
  const fd = new FormData();
  fd.append("phone", phone);
  fd.append("otp", otp);
  const res = await fetch(`${API_BASE}/api/auth/account/delete`, { method: "POST", body: fd });
  return handle(res);
}

/**
 * Report a new issue (multipart). Returns either the created issue or, when a
 * nearby duplicate is found and force=false, { duplicate_exists, existing_issue }.
 */
export async function reportIssue({
  imageFile,
  audioBlob,
  latitude,
  longitude,
  userId,
  title = "Street Issue",
  force = false,
}) {
  const fd = new FormData();
  fd.append("latitude", String(latitude));
  fd.append("longitude", String(longitude));
  fd.append("user_id", userId);
  fd.append("title", title);
  fd.append("force", String(force));
  if (imageFile) fd.append("image", imageFile);
  if (audioBlob) {
    // Give the blob a filename so FastAPI's UploadFile.filename is populated.
    const file = new File([audioBlob], "voice-note.webm", {
      type: audioBlob.type || "audio/webm",
    });
    fd.append("audio", file);
  }

  const res = await fetch(`${API_BASE}/api/issues/report`, {
    method: "POST",
    body: fd,
  });
  return handle(res);
}

/** Upvote an issue (one per user). `name` is the OTP-verified upvoter name. */
export async function upvoteIssue(issueId, userId, name = "") {
  const fd = new FormData();
  fd.append("user_id", userId);
  if (name) fd.append("name", name);
  const res = await fetch(`${API_BASE}/api/issues/${issueId}/upvote`, {
    method: "POST",
    body: fd,
  });
  return handle(res);
}

/** Fetch issues within `radius` meters of (lat, lng). */
export async function fetchNearby(lat, lng, radius = 500) {
  const url = `${API_BASE}/api/issues/nearby?lat=${lat}&lng=${lng}&radius=${radius}`;
  const res = await fetch(url);
  return handle(res);
}

/** Fetch a user's submission history. */
export async function fetchHistory(userId) {
  const res = await fetch(`${API_BASE}/api/issues/history/${userId}`);
  return handle(res);
}

/** Fetch the real GCC zone + ward boundary polygons (GeoJSON) for the maps. */
export async function fetchBoundaries() {
  const res = await fetch(`${API_BASE}/api/boundaries`);
  return handle(res);
}

/** Fetch public (verified) grievances in a given ward. */
export async function fetchWardIssues(wardNo) {
  const res = await fetch(`${API_BASE}/api/issues/ward/${wardNo}`);
  return handle(res);
}

/**
 * Resolve a coordinate to its real GCC zone + ward via point-in-polygon over
 * the KML boundaries. Returns { zone, zone_name, region, ward, inside }.
 */
export async function locateBoundary(lat, lng) {
  const res = await fetch(`${API_BASE}/api/locate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ latitude: lat, longitude: lng }),
  });
  return handle(res);
}

/** Save phone number (and optional name) after OTP verification. */
export async function confirmIssue(issueId, phone, name = "") {
  const fd = new FormData();
  fd.append("phone", phone);
  if (name) fd.append("name", name);
  const res = await fetch(`${API_BASE}/api/issues/${issueId}/confirm`, {
    method: "POST",
    body: fd,
  });
  return handle(res);
}

/** Citizen verification: response is "APPROVED" or "REJECTED". */
export async function verifyIssue(issueId, userId, response) {
  const fd = new FormData();
  fd.append("user_id", userId);
  fd.append("response", response);
  const res = await fetch(`${API_BASE}/api/issues/${issueId}/verify`, {
    method: "POST",
    body: fd,
  });
  return handle(res);
}

/** Admin: filterable issue queue (status, zone, ward, coordinator, department,
 *  constituency, q free-text). Omitted filters return the full set. */
export async function fetchAdminIssues({
  status, sort, zone, ward, coordinator, department, constituency, q,
  unassigned, since, board, limit, offset,
} = {}) {
  const params = new URLSearchParams();
  if (status)       params.set("status", status);
  if (sort)         params.set("sort", sort);
  if (zone)         params.set("zone", zone);
  if (ward != null && ward !== "") params.set("ward", ward);
  if (coordinator)  params.set("coordinator", coordinator);
  if (department)   params.set("department", department);
  if (constituency) params.set("constituency", constituency);
  if (q)            params.set("q", q);
  if (unassigned)   params.set("unassigned", "true");
  if (since)        params.set("since", since);
  if (board)        params.set("board", "true");
  if (limit != null) params.set("limit", limit);
  if (offset)       params.set("offset", offset);
  const qs = params.toString();
  const res = await fetch(`${API_BASE}/api/admin/issues${qs ? `?${qs}` : ""}`, {
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Admin: per-status counts for the ticket queue (cheap aggregate for the tab
 *  badges, so the list can page without the browser counting every row). */
export async function fetchAdminIssueStats({
  zone, ward, coordinator, department, constituency, q, unassigned, since,
} = {}) {
  const params = new URLSearchParams();
  if (zone)         params.set("zone", zone);
  if (ward != null && ward !== "") params.set("ward", ward);
  if (coordinator)  params.set("coordinator", coordinator);
  if (department)   params.set("department", department);
  if (constituency) params.set("constituency", constituency);
  if (q)            params.set("q", q);
  if (unassigned)   params.set("unassigned", "true");
  if (since)        params.set("since", since);
  const qs = params.toString();
  const res = await fetch(`${API_BASE}/api/admin/issues/stats${qs ? `?${qs}` : ""}`, {
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Admin: the signed-in MLA office (tenant) — its constituency, wards and zones.
 *  The console narrows every picker and map to this. */
export async function fetchAdminTenant() {
  const res = await fetch(`${API_BASE}/api/admin/tenant`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: list all coordinator accounts (used for the assign picker). */
export async function fetchCoordinators() {
  const res = await fetch(`${API_BASE}/api/admin/coordinators`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: log a walk-in grievance directly into the workflow (created ACTIVE).
 *  `fields` may include title, description, name, phone, ward, department,
 *  coordinator and a photo File. */
export async function adminCreateGrievance(fields = {}) {
  const fd = new FormData();
  Object.entries(fields).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") fd.append(k, v);
  });
  const res = await fetch(`${API_BASE}/api/admin/issues`, {
    method: "POST",
    headers: adminHeaders(),
    body: fd,
  });
  return handle(res);
}

/** Admin: assign (or reassign) a grievance to a coordinator; empty un-assigns. */
export async function adminAssignCoordinator(issueId, coordinator) {
  const fd = new FormData();
  fd.append("coordinator", coordinator || "");
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/assign`, {
    method: "POST",
    headers: adminHeaders(),
    body: fd,
  });
  return handle(res);
}

/** Admin: list citizen accounts with per-user report/resolved/open counters. */
export async function fetchAdminUsers({ q } = {}) {
  const qs = q ? `?q=${encodeURIComponent(q)}` : "";
  const res = await fetch(`${API_BASE}/api/admin/users${qs}`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: fetch all configured responsible-officer contacts as a
 *  { "<Dept>||<SubDept>||<Officer>": {name, mobile} } map. */
export async function fetchOfficerContacts() {
  const res = await fetch(`${API_BASE}/api/admin/officers`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: create/update one officer contact (name + mobile) by its key. */
export async function saveOfficerContact({ key, name = "", mobile = "" }) {
  const res = await fetch(`${API_BASE}/api/admin/officers`, {
    method: "PUT",
    headers: adminHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify({ key, name, mobile }),
  });
  return handle(res);
}

/** Admin: the append-only action history for one grievance.
 *
 *  The issue row only carries the LATEST coordinator_message, so this is the
 *  only way to see the note written at transfer time after a later escalate
 *  overwrote it — together with the photo/voice recorded for each action.
 */
export async function fetchIssueTimeline(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/timeline`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: read the citizen's attached petition with Gemini and return a
 *  point-wise summary. A manual action — reading a document costs a model
 *  call, so it is never triggered just by opening a ticket. Cached server-side
 *  after the first read; pass refresh to re-read. */
export async function summariseDocument(issueId, { refresh = false } = {}) {
  const res = await fetch(
    `${API_BASE}/api/admin/issues/${issueId}/summarise-document${refresh ? "?refresh=true" : ""}`,
    { method: "POST", headers: adminHeaders() }
  );
  return handle(res);
}

/** Admin: per-coordinator workload and outcomes (assigned / escalated /
 *  resolved / false, closure rate and average turnaround). */
export async function fetchCoordinatorPerformance() {
  const res = await fetch(`${API_BASE}/api/admin/coordinator-performance`, { headers: adminHeaders() });
  return handle(res);
}

/** Admin: approve a submitted grievance -> ACTIVE (makes it public). */
export async function adminVerifyGrievance(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/verify`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}

/* ── Duplicates: review, merge, undo ──────────────────────────────────────
 * Detection runs on the backend when a report arrives; ruling on it is staff
 * work. The citizen is never asked and never sees these.
 * ──────────────────────────────────────────────────────────────────────── */

/** The suspected original, plus any reports already merged into this one. */
export async function fetchDuplicateContext(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/duplicate`, {
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Fold this grievance into the one it duplicates. */
export async function adminMergeDuplicate(issueId, parentId) {
  const fd = new FormData();
  fd.append("parent_id", parentId);
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/merge`, {
    method: "POST",
    headers: adminHeaders(),
    body: fd,
  });
  return handle(res);
}

/** Rule that the flagged grievance is a different problem after all. */
export async function adminKeepSeparate(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/keep-separate`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Reverse a merge — restores the grievance as its own ticket. */
export async function adminUnmergeDuplicate(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/unmerge`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Retry a transcription/routing that failed in the background. */
export async function adminReprocessIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/reprocess`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}

/* ── Coordinator action endpoints (update the citizen-facing status) ── */

/** Coordinator ward listing — includes every status (SUBMITTED, ACTIVE, …). */
export async function fetchCoordinatorWardIssues(wardNo) {
  const res = await fetch(`${API_BASE}/api/coordinator/ward/${wardNo}`);
  return handle(res);
}

/** Coordinator "Verify Grievance" (take ownership) → status ACTIVE ("Assigned"). */
export async function coordinatorVerify(issueId) {
  const res = await fetch(`${API_BASE}/api/coordinator/issues/${issueId}/verify`, { method: "POST" });
  return handle(res);
}

/** Coordinator "Dept Transfer" → FORWARDED (labeled "Inspection"), routes to a department. */
export async function coordinatorTransfer(issueId, department, notes = "") {
  const fd = new FormData();
  fd.append("department", department);
  if (notes) fd.append("notes", notes);
  const res = await fetch(`${API_BASE}/api/coordinator/issues/${issueId}/transfer`, { method: "POST", body: fd });
  return handle(res);
}

/** Coordinator "Redirect" → SUBMITTED with a delay-apology message. */
export async function coordinatorRedirect(issueId, description) {
  const fd = new FormData();
  fd.append("description", description);
  const res = await fetch(`${API_BASE}/api/coordinator/issues/${issueId}/redirect`, { method: "POST", body: fd });
  return handle(res);
}

/** Coordinator "Close" → PENDING_VERIFICATION (citizen sees the verify prompt). */
export async function coordinatorClose(issueId, notes = "") {
  const fd = new FormData();
  if (notes) fd.append("notes", notes);
  const res = await fetch(`${API_BASE}/api/coordinator/issues/${issueId}/close`, { method: "POST", body: fd });
  return handle(res);
}

/** Coordinator "False Petition" → FALSE with the coordinator's reason. */
export async function coordinatorMarkFalse(issueId, reason, details = "") {
  const fd = new FormData();
  fd.append("reason", reason);
  if (details) fd.append("details", details);
  const res = await fetch(`${API_BASE}/api/coordinator/issues/${issueId}/mark_false`, { method: "POST", body: fd });
  return handle(res);
}

/** Admin: forward a verified ticket to its department -> FORWARDED. */
export async function adminForwardIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/forward`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}

/** Admin: mark resolved -> PENDING_VERIFICATION. */
export async function adminCloseIssue(issueId, { note = "", photo = null, voice = null } = {}) {
  // Proof of work travels with the closure, the same pair the coordinator app
  // has always required, so both routes to "resolved" mean the same thing.
  const body = new FormData();
  body.append("note", note);
  if (photo) body.append("photo", photo, photo.name || "proof.jpg");
  // Name the file for what the recorder produced: the backend keeps the
  // extension, and players go by it.
  if (voice) body.append("voice", voice, /mp4|aac/.test(voice.type || "") ? "proof.m4a" : "proof.webm");
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/close`, {
    method: "POST",
    headers: adminHeaders(),
    body,
  });
  return handle(res);
}

/** Admin: accept an ACTIVE ticket -> IN_PROGRESS. */
export async function adminStartIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/progress`, {
    method: "POST",
    headers: adminHeaders(),
  });
  return handle(res);
}


/* ── Service Hub — Gemini chatbot ─────────────────────────────────────────── */

/**
 * Send a chat message to the Service Hub Gemini assistant.
 * @param {object} args
 * @param {string} args.message         The citizen's message.
 * @param {Array<{role:"user"|"assistant", text:string}>} [args.history]
 * @param {object} [args.portal]        Optional portal context {name, tagline, url, description}.
 * @returns {Promise<{reply:string, mock?:boolean}>}
 */
export async function serviceHubChat({ message, history = [], portal = null }) {
  const res = await fetch(`${API_BASE}/api/servicehub/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, history, portal }),
  });
  return handle(res);
}
