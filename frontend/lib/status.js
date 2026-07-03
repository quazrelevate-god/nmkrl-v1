/**
 * lib/status.js
 * -------------
 * Single source of truth for mapping backend status enums to user-facing
 * labels and Tailwind color classes. Keeps badges/pins consistent everywhere.
 */

export const STATUS_META = {
  SUBMITTED: {
    label: "Pending Verification",
    badge: "bg-violet-100 text-violet-700 border border-violet-200",
    pin: "#7c3aed", // violet
    open: true,
  },
  ACTIVE: {
    label: "Assigned",
    badge: "bg-blue-100 text-blue-700 border border-blue-200",
    pin: "#2563eb", // blue
    open: true,
  },
  IN_PROGRESS: {
    label: "In Progress",
    badge: "bg-orange-100 text-orange-700 border border-orange-200",
    pin: "#f97316", // orange
    open: true,
  },
  PENDING_VERIFICATION: {
    label: "Verification Pending",
    badge: "bg-amber-100 text-amber-800 border border-amber-200",
    pin: "#d97706", // amber
    open: true,
  },
  CLOSED: {
    label: "Resolved",
    badge: "bg-green-100 text-green-700 border border-green-200",
    pin: "#16a34a", // green
    open: false,
  },
};

export function statusMeta(status) {
  return STATUS_META[status] || STATUS_META.ACTIVE;
}
