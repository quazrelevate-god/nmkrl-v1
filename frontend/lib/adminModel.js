/**
 * lib/adminModel.js
 * -----------------
 * Presentation helpers for the revamped "Petition Management" staff portal.
 * The backend lifecycle statuses are mapped to the reference-design labels and
 * a few display-only fields (priority, SLA "open for", ticket/token numbers) are
 * derived from the real issue data so the queue reads like the reference UI.
 *
 * Backend status  →  Portal label
 *   SUBMITTED             Pending Verification   (lives in Petition Review)
 *   ACTIVE                Open
 *   FORWARDED             Forwarded
 *   IN_PROGRESS           In Progress
 *   PENDING_VERIFICATION  Resolved
 *   CLOSED                Closed
 */

import { departmentMeta } from "@/lib/departments";

export const PORTAL_STATUS = {
  SUBMITTED:            { label: "Pending Verification", badge: "bg-violet-50 text-violet-700 ring-1 ring-violet-200" },
  ACTIVE:              { label: "Open",         badge: "bg-blue-50 text-blue-600 ring-1 ring-blue-200" },
  FORWARDED:           { label: "Forwarded",    badge: "bg-indigo-50 text-indigo-600 ring-1 ring-indigo-200" },
  IN_PROGRESS:         { label: "In Progress",  badge: "bg-amber-50 text-amber-700 ring-1 ring-amber-200" },
  PENDING_VERIFICATION:{ label: "Resolved",     badge: "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200" },
  CLOSED:              { label: "Closed",       badge: "bg-slate-100 text-slate-500 ring-1 ring-slate-200" },
};

export function portalStatus(status) {
  return PORTAL_STATUS[status] || PORTAL_STATUS.ACTIVE;
}

/** The tab buckets shown on the Tickets page (SUBMITTED lives in Petition Review). */
export const TICKET_TABS = [
  { key: "",            label: "All",         match: null },
  { key: "ACTIVE",      label: "Open",        match: ["ACTIVE"] },
  { key: "IN_PROGRESS", label: "In Progress", match: ["IN_PROGRESS"] },
  { key: "FORWARDED",   label: "Forwarded",   match: ["FORWARDED"] },
  { key: "PENDING_VERIFICATION", label: "Resolved", match: ["PENDING_VERIFICATION"] },
  { key: "CLOSED",      label: "Closed",      match: ["CLOSED"] },
];

/** Every status that belongs on the Tickets board (everything past verification). */
export const TICKET_STATUSES = ["ACTIVE", "FORWARDED", "IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED"];

/* ── Priority (derived) ───────────────────────────────────────────────────────
   No priority is stored, so we derive it from civic signal: how many citizens
   upvoted + how tight the routed department's SLA is. Deterministic. */
export const PRIORITY_META = {
  High:   { badge: "bg-red-500 text-white", dot: "#ef4444", rank: 3 },
  Medium: { badge: "bg-amber-400 text-amber-950", dot: "#f59e0b", rank: 2 },
  Low:    { badge: "bg-slate-200 text-slate-600", dot: "#94a3b8", rank: 1 },
};

export function derivePriority(issue) {
  const up = issue.upvotes || 0;
  const sla = departmentMeta(issue.department).slaDays;
  const score = (up >= 15 ? 2 : up >= 5 ? 1 : 0) + (sla <= 3 ? 2 : sla <= 7 ? 1 : 0);
  if (score >= 3) return "High";
  if (score >= 1) return "Medium";
  return "Low";
}

/* ── Ticket + token numbers (reference style) ─────────────────────────────── */
/** TKT-YYYY-NNNNN from the issue id + created year (deterministic, display-only). */
export function ticketNo(issue) {
  const year = issue.created_at ? new Date(issue.created_at).getFullYear() : new Date().getFullYear();
  const hex = (issue.id || "").replace(/-/g, "").slice(0, 6);
  const n = (parseInt(hex, 16) % 100000).toString().padStart(5, "0");
  return `TKT-${year}-${n}`;
}

/** TKN token: YYYYMMDD + short id tail — mirrors the reference token style. */
export function tokenNo(issue) {
  const d = issue.created_at ? new Date(issue.created_at) : new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  const tail = (issue.id || "").replace(/-/g, "").slice(-5).replace(/\D/g, "0").padStart(5, "0");
  return `TKN${ymd}${tail}`;
}

/* ── SLA / "open for" ─────────────────────────────────────────────────────── */
export function daysOpen(issue) {
  if (!issue.created_at) return 0;
  return Math.max(0, Math.floor((Date.now() - new Date(issue.created_at).getTime()) / 86400000));
}

/** SLA window in whole weeks (from the routed department), e.g. "4W SLA". */
export function slaWeeksLabel(issue) {
  const sla = departmentMeta(issue.department).slaDays;
  const weeks = Math.max(1, Math.round(sla / 7 * 2)); // 2d→1W, 7d→2W, 14d→4W
  return `${weeks}W SLA`;
}

/** Is the ticket past its SLA window (breached)? */
export function slaBreached(issue) {
  if (["PENDING_VERIFICATION", "CLOSED"].includes(issue.status)) return false;
  return daysOpen(issue) > departmentMeta(issue.department).slaDays;
}

/* ── Citizen identity ─────────────────────────────────────────────────────── */
export function citizenName(issue) {
  const n = (issue.name || "").trim();
  if (n) return n;
  // No name captured — fall back to a clean masked-phone identity.
  const phone = (issue.phone || "").toString();
  if (phone.length >= 4) return `Citizen ••${phone.slice(-4)}`;
  return "Unknown Citizen";
}

export function initials(name) {
  return (name || "?")
    .replace(/[^A-Za-z஀-௿ ]/g, "")
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join("")
    .toUpperCase() || "?";
}
