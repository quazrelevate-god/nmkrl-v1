/**
 * lib/departments.js
 * ------------------
 * Display metadata for the 7 municipal departments grievances route to.
 * Keys MUST match the canonical names returned by the backend Gemini router
 * (see backend/gemini_service.py DEPARTMENTS).
 *
 *  - slaDays : mock service-level-agreement window used for the WhatsApp dispatch
 *  - phone   : mock department WhatsApp number (showcase only)
 *  - badge   : Tailwind classes for the department chip
 */

export const DEPARTMENTS = {
  "Solid Waste Management Department": {
    short: "Solid Waste", slaDays: 2, phone: "+91 90031 00001",
    badge: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  },
  "Electrical Department": {
    short: "Electrical", slaDays: 3, phone: "+91 90031 00002",
    badge: "bg-yellow-50 text-yellow-700 ring-yellow-200",
  },
  "Works & Roads Department": {
    short: "Works & Roads", slaDays: 14, phone: "+91 90031 00003",
    badge: "bg-stone-100 text-stone-700 ring-stone-300",
  },
  "Storm Water Drain Department": {
    short: "Storm Water", slaDays: 7, phone: "+91 90031 00004",
    badge: "bg-cyan-50 text-cyan-700 ring-cyan-200",
  },
  "Public Health Department": {
    short: "Public Health", slaDays: 3, phone: "+91 90031 00005",
    badge: "bg-rose-50 text-rose-700 ring-rose-200",
  },
  "Parks & Playfields Department": {
    short: "Parks & Playfields", slaDays: 10, phone: "+91 90031 00006",
    badge: "bg-lime-50 text-lime-700 ring-lime-200",
  },
  "Allied Utilities": {
    short: "Allied Utilities", slaDays: 5, phone: "+91 90031 00007",
    badge: "bg-indigo-50 text-indigo-700 ring-indigo-200",
  },
};

const FALLBACK = {
  short: "Unassigned", slaDays: 7, phone: "+91 90031 00000",
  badge: "bg-slate-100 text-slate-600 ring-slate-200",
};

export function departmentMeta(name) {
  return DEPARTMENTS[name] || FALLBACK;
}

/** Compute the SLA deadline date from a created_at ISO string + dept window. */
export function slaDeadline(createdAtIso, name) {
  const meta = departmentMeta(name);
  const base = createdAtIso ? new Date(createdAtIso) : new Date();
  const d = new Date(base.getTime() + meta.slaDays * 24 * 60 * 60 * 1000);
  return d;
}
