/**
 * lib/status.js
 * -------------
 * Single source of truth for mapping backend status enums to user-facing
 * labels and Tailwind color classes. Keeps badges/pins consistent everywhere.
 */

export const STATUS_META = {
  SUBMITTED: {
    label: "Pending Verification",
    badge: "bg-slate-100 text-slate-600 border border-slate-200",
    pin: "#64748b", // slate
    open: true,
  },
  ACTIVE: {
    label: "Assigned",
    badge: "bg-brand-100 text-brand-700 border border-brand-200",
    pin: "#0f5641", // algae green (brand)
    open: true,
  },
  FORWARDED: {
    // Coordinator's "Dept. Transfer" moves the ticket into an Inspection state.
    label: "Inspection",
    badge: "bg-sky-50 text-sky-700 border border-sky-100",
    pin: "#0284c7",
    open: true,
  },
  IN_PROGRESS: {
    label: "In Progress",
    badge: "bg-sky-50 text-sky-700 border border-sky-100",
    pin: "#0284c7",
    open: true,
  },
  PENDING_VERIFICATION: {
    label: "Verification Pending",
    badge: "bg-amber-50 text-amber-700 border border-amber-100",
    pin: "#c99a3a",
    open: true,
  },
  CLOSED: {
    label: "Resolved",
    badge: "bg-emerald-50 text-emerald-700 border border-emerald-100",
    pin: "#0d9488",
    open: false,
  },
  FALSE: {
    label: "Marked as false petition",
    badge: "bg-rose-50 text-rose-700 border border-rose-100",
    pin: "#e11d48",
    open: false,
  },
};

export function statusMeta(status) {
  return STATUS_META[status] || STATUS_META.ACTIVE;
}
