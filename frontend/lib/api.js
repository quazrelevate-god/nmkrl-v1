/**
 * lib/api.js
 * ----------
 * Thin, typed-ish wrapper around the FastAPI backend. Centralises the base URL,
 * error handling, and the multipart/form-data plumbing so screens stay clean.
 *
 * The integration boundary: every function here maps 1:1 to a backend route in
 * routers/issues.py or routers/admin.py.
 */

// /fms prefix is proxied by Next.js rewrites → FastAPI on localhost:8000.
// Override with NEXT_PUBLIC_API_BASE=http://... to call FastAPI directly.
export const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "/fms";

/** Resolve a stored media path (e.g. "/uploads/..") to an absolute URL. */
export function mediaUrl(path) {
  if (!path) return null;
  if (path.startsWith("http")) return path;
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

/** Admin: filterable issue queue (by status, zone, ward). */
export async function fetchAdminIssues({ status, sort, zone, ward } = {}) {
  const params = new URLSearchParams();
  if (status) params.set("status", status);
  if (sort)   params.set("sort", sort);
  if (zone)   params.set("zone", zone);
  if (ward != null && ward !== "") params.set("ward", ward);
  const qs = params.toString();
  const res = await fetch(`${API_BASE}/api/admin/issues${qs ? `?${qs}` : ""}`);
  return handle(res);
}

/** Admin: approve a submitted grievance -> ACTIVE (makes it public). */
export async function adminVerifyGrievance(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/verify`, {
    method: "POST",
  });
  return handle(res);
}

/** Admin: forward a verified ticket to its department -> FORWARDED. */
export async function adminForwardIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/forward`, {
    method: "POST",
  });
  return handle(res);
}

/** Admin: mark resolved -> PENDING_VERIFICATION. */
export async function adminCloseIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/close`, {
    method: "POST",
  });
  return handle(res);
}

/** Admin: accept an ACTIVE ticket -> IN_PROGRESS. */
export async function adminStartIssue(issueId) {
  const res = await fetch(`${API_BASE}/api/admin/issues/${issueId}/progress`, {
    method: "POST",
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
