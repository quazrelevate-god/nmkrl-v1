/**
 * lib/coordinatorActions.js
 * -------------------------
 * Read-only helpers for the admin panel to surface coordinator petition
 * actions (redirect / close / transfer / false) from the shared localStorage
 * bucket that CoordinatorProvider writes to.
 */

const ACTIONS_KEY = "fms_coord_petition_actions";

export const ACTION_KINDS = {
  redirect: { label: "Redirected", tone: "bg-slate-100 text-slate-700 ring-slate-200" },
  transfer: { label: "Transferred", tone: "bg-brand-50 text-brand-700 ring-brand-200" },
  close:    { label: "Closed",      tone: "bg-emerald-50 text-emerald-700 ring-emerald-200" },
  false:    { label: "False Petition", tone: "bg-rose-50 text-rose-700 ring-rose-200" },
};

export function loadCoordinatorActions() {
  if (typeof window === "undefined") return [];
  try { return JSON.parse(localStorage.getItem(ACTIONS_KEY) || "[]"); }
  catch { return []; }
}
