/**
 * lib/deptRouting.js
 * ------------------
 * Department routing for the admin portal, driven by the Tamil Nadu grievance
 * taxonomy in /public/departments.json:
 *
 *   Government Department → Grievance Type → Grievance SubType
 *                        → Sub Department → Responsible Officer
 *
 * The AI summary of a ticket is (mock-)resolved to a leaf in this tree, and the
 * responsible officer's manually-entered contact (name + mobile) is looked up
 * from the departmental configuration (localStorage).
 */

let _treePromise = null;

/** Fetch + cache the compact department tree ({ "<Dept>": { "<Type>": { "<SubType>": {sd, ro} } } }). */
export function loadDeptTree() {
  if (!_treePromise) {
    _treePromise = fetch("/departments.json")
      .then((r) => r.json())
      .then((j) => j.departments || {})
      .catch(() => ({}));
  }
  return _treePromise;
}

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return Math.abs(h);
}

/**
 * Map the app's coarse (Gemini) department name → a formal Government Department
 * in the taxonomy, so a ticket routes somewhere sensible. Unknown/absent
 * departments fall back to a deterministic pick.
 */
export const APP_TO_GOV = {
  "Solid Waste Management Department": "Municipal Administration and Water Supply Department (MAWS)",
  "Electrical Department": "Energy Department (ENERGY)",
  "Works & Roads Department": "Highways and Minor Ports Department (HWY)",
  "Storm Water Drain Department": "Municipal Administration and Water Supply Department (MAWS)",
  "Public Health Department": "Health and Family Welfare Department (HEALTH)",
  "Parks & Playfields Department": "Municipal Administration and Water Supply Department (MAWS)",
  "Allied Utilities": "Municipal Administration and Water Supply Department (MAWS)",
};

/**
 * Real (non-mock) routing: the Government Department an issue actually belongs
 * to, from its STORED `department` (the coordinator/Gemini value), mapped to the
 * taxonomy. Returns null when the issue has no department or it maps nowhere —
 * callers bucket those under "Unrouted" rather than inventing a destination.
 */
export function resolveGovDept(issue, tree) {
  const app = (issue?.department || "").trim();
  if (!app) return null;
  const mapped = APP_TO_GOV[app];
  if (mapped && tree?.[mapped]) return mapped;   // app dept → gov dept
  if (tree?.[app]) return app;                   // already a government department
  return null;
}

/** All Government Departments in the taxonomy (sorted). */
export function govDepartments(tree) {
  return Object.keys(tree || {}).sort();
}

/** Flatten one department's leaves → [{ type, subtype, subDepts[], officers[] }]. */
export function deptLeaves(tree, deptName) {
  const d = tree?.[deptName];
  if (!d) return [];
  const out = [];
  for (const [type, subs] of Object.entries(d))
    for (const [subtype, node] of Object.entries(subs))
      out.push({ type, subtype, subDepts: node.sd || [], officers: node.ro || [] });
  return out;
}

/**
 * Resolve a ticket to its routing chain. Deterministic (keyed on the ticket id)
 * so a ticket always lands on the same leaf.
 */
export function resolveRouting(issue, tree) {
  if (!tree || !Object.keys(tree).length) return null;
  const keys = Object.keys(tree);
  const govDept = (tree[APP_TO_GOV[issue.department]] && APP_TO_GOV[issue.department])
    || keys[hash(String(issue.id || issue.title || "x")) % keys.length];
  const leaves = deptLeaves(tree, govDept);
  if (!leaves.length) return null;
  const seed = String(issue.id || issue.title || "x");
  const leaf = leaves[hash(seed) % leaves.length];
  const subDept = leaf.subDepts[0] || "General Administration";
  const officer = leaf.officers.length
    ? leaf.officers[hash(seed + "o") % leaf.officers.length]
    : "Public Grievance Officer";
  return {
    govDept,
    type: leaf.type,
    subtype: leaf.subtype,
    subDept,
    officer,
    officers: leaf.officers,
  };
}

/**
 * For the config UI: within a department, group unique Responsible Officers by
 * their Sub Department → [{ subDept, officers[] }].
 */
export function deptOfficerGroups(tree, deptName) {
  const d = tree?.[deptName];
  if (!d) return [];
  const map = new Map(); // subDept -> Set(officer)
  for (const subs of Object.values(d))
    for (const node of Object.values(subs)) {
      const sds = node.sd?.length ? node.sd : ["General Administration"];
      for (const sd of sds) {
        if (!map.has(sd)) map.set(sd, new Set());
        for (const o of node.ro || []) map.get(sd).add(o);
      }
    }
  return [...map.entries()]
    .map(([subDept, offs]) => ({ subDept, officers: [...offs].sort() }))
    .sort((a, b) => a.subDept.localeCompare(b.subDept));
}

/** Total unique (subDept, officer) rows in a department. */
export function deptOfficerCount(tree, deptName) {
  return deptOfficerGroups(tree, deptName).reduce((s, g) => s + g.officers.length, 0);
}

/* ── Officer contact configuration (localStorage) ── */
const CONFIG_KEY = "nk_dept_officer_contacts";

export function contactKey(deptName, subDept, officer) {
  return `${deptName}||${subDept}||${officer}`;
}
export function loadContacts() {
  if (typeof window === "undefined") return {};
  try { return JSON.parse(localStorage.getItem(CONFIG_KEY) || "{}"); } catch { return {}; }
}
export function saveContacts(obj) {
  try {
    localStorage.setItem(CONFIG_KEY, JSON.stringify(obj));
    window.dispatchEvent(new Event("nk:dept-contacts-changed"));
  } catch { /* ignore */ }
}
export function getContact(deptName, subDept, officer) {
  return loadContacts()[contactKey(deptName, subDept, officer)] || null;
}
/** Best-effort contact lookup for a routing result (tries its subDept, then any). */
export function contactForRouting(routing) {
  if (!routing) return null;
  const all = loadContacts();
  const exact = all[contactKey(routing.govDept, routing.subDept, routing.officer)];
  if (exact) return exact;
  // fall back: any configured contact for this officer in this department
  const prefix = `${routing.govDept}||`;
  const suffix = `||${routing.officer}`;
  const hit = Object.keys(all).find((k) => k.startsWith(prefix) && k.endsWith(suffix));
  return hit ? all[hit] : null;
}
