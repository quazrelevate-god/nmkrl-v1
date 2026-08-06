"use client";

/**
 * /admin/coordinators — Coordinator user management.
 *
 * Admin can:
 *   • Create a new coordinator (username, temp password, name, role, constituency, ward)
 *   • Edit an assignment (role / constituency / ward)
 *   • Reset password (generates a temp password, optionally forces change on login)
 *   • Disable / re-enable an account (soft, preserves history)
 *
 * State lives in localStorage via lib/coordinators.js so admin actions persist
 * across reloads and are picked up by the coordinator login flow.
 */

import { useEffect, useMemo, useState } from "react";
import {
  Users, Plus, Search, X, MoreVertical, KeyRound, Pencil, ShieldBan,
  ShieldCheck, RefreshCcw, MapPin, Building2, UserPlus, Copy, Check,
  CheckCircle2, AlertCircle,
} from "lucide-react";
import {
  listCoordinators, listCoordinatorsRemote, ensureSeedCoordinators,
  createCoordinatorRemote, updateCoordinatorRemote, initialsFrom,
} from "@/lib/coordinators";
import { CONSTITUENCIES, CHENNAI_AC_MAP } from "@/lib/constituencies";

const ROLES = ["Ward Coordinator", "Constituency PA", "Constituency Lead", "Field Officer"];

// This admin console is scoped to the MLA's home constituency by default —
// Egmore. Admin can still switch via the toolbar dropdown when needed.
const DEFAULT_CONSTITUENCY = "16 - Egmore";

/** Generates a temp password like "Nkr-4823" — friendly to say on a call. */
function generatePassword() {
  const n = Math.floor(1000 + Math.random() * 9000);
  const prefixes = ["Nkr", "Ward", "PA", "TN"];
  return `${prefixes[Math.floor(Math.random() * prefixes.length)]}-${n}`;
}

export default function CoordinatorsPage() {
  const [rows, setRows] = useState([]);
  const [query, setQuery] = useState("");
  const [filterConst, setFilterConst] = useState(DEFAULT_CONSTITUENCY);
  const [filterStatus, setFilterStatus] = useState("");

  // One drawer for both "Add" and "Edit", one dialog for password reset,
  // one for disable/enable confirmations. Kept as sibling states to make the
  // page's state easy to read at a glance.
  const [editingUser, setEditingUser] = useState(null);   // null | "new" | username
  const [resetTarget, setResetTarget] = useState(null);   // coordinator | null
  const [statusTarget, setStatusTarget] = useState(null); // coordinator | null
  const [toast, setToast] = useState(null);

  // Source of truth is the backend so every browser + the mobile app agree.
  // Falls back to the local seed only if the backend is unreachable.
  async function refresh() {
    try {
      setRows(await listCoordinatorsRemote());
    } catch {
      setRows(listCoordinators());
    }
  }

  useEffect(() => {
    // Make sure the 4 demo accounts exist in the backend, then load the list.
    ensureSeedCoordinators().finally(refresh);
    const sync = () => refresh();
    window.addEventListener("fms:coordinator-directory-changed", sync);
    return () => window.removeEventListener("fms:coordinator-directory-changed", sync);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((c) => {
      if (filterConst && c.constituency !== filterConst) return false;
      if (filterStatus && c.status !== filterStatus) return false;
      if (!q) return true;
      return (
        c.name?.toLowerCase().includes(q) ||
        c.username?.toLowerCase().includes(q) ||
        c.role?.toLowerCase().includes(q) ||
        c.constituency?.toLowerCase().includes(q) ||
        String(c.homeWard || "").includes(q)
      );
    });
  }, [rows, query, filterConst, filterStatus]);

  const activeCount = rows.filter((c) => c.status !== "disabled").length;
  const disabledCount = rows.length - activeCount;

  return (
    <>
      {/* Header */}
      <header className="glass-panel z-10 flex items-center justify-between px-7 py-4">
        <div className="flex items-center gap-3">
          <div className="glass-panel flex h-10 w-10 items-center justify-center rounded-xl text-brand">
            <Users size={20} />
          </div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">Coordinators</h1>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">
              MLA Office · Ward and Constituency staff
            </p>
          </div>
        </div>
        <button
          onClick={() => setEditingUser("new")}
          className="accent-ring flex items-center gap-2 rounded-xl bg-gradient-to-r from-brand to-brand-dark px-4 py-2.5 text-sm font-bold text-white shadow-lg shadow-brand/30 transition hover:-translate-y-px"
        >
          <UserPlus size={16} className="text-amber-300" /> Add coordinator
        </button>
      </header>

      {/* Body */}
      <div className="min-h-0 flex-1 overflow-y-auto px-7 py-5">
        {/* Stat pills */}
        <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
          <StatPill label="Total" value={rows.length} icon={Users} tone="text-slate-800" />
          <StatPill label="Active" value={activeCount} icon={ShieldCheck} tone="text-emerald-600" />
          <StatPill label="Disabled" value={disabledCount} icon={ShieldBan} tone="text-slate-500" />
          <StatPill
            label="Constituencies"
            value={new Set(rows.map((c) => c.constituency)).size}
            icon={Building2}
            tone="text-brand"
          />
        </div>

        {/* Toolbar */}
        <div className="glass-panel mb-4 flex flex-wrap items-center gap-2 rounded-2xl px-3 py-2.5">
          <div className="glass-panel flex min-w-[260px] flex-1 items-center gap-2.5 rounded-xl px-3 py-2">
            <Search size={16} className="text-slate-400" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name, username, ward, or constituency"
              className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400"
            />
            {query && (
              <button onClick={() => setQuery("")} className="text-slate-400 hover:text-slate-600">
                <X size={14} />
              </button>
            )}
          </div>

          <select
            value={filterConst}
            onChange={(e) => setFilterConst(e.target.value)}
            className="glass-panel h-10 min-w-[180px] rounded-xl bg-white/60 px-3 text-sm font-semibold text-slate-700 outline-none"
          >
            <option value="">All constituencies</option>
            {CONSTITUENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>

          <div className="glass-panel flex items-center gap-1 rounded-xl p-1">
            {[
              { key: "", label: "All" },
              { key: "active", label: "Active" },
              { key: "disabled", label: "Disabled" },
            ].map((s) => (
              <button
                key={s.key}
                onClick={() => setFilterStatus(s.key)}
                className={`rounded-lg px-2.5 py-1.5 text-[11px] font-bold transition ${
                  filterStatus === s.key
                    ? "bg-brand text-white shadow-sm"
                    : "text-slate-600 hover:bg-slate-900/5"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>

        {/* List */}
        {filtered.length ? (
          <div className="space-y-2.5">
            {filtered.map((c) => (
              <CoordinatorRow
                key={c.username}
                coord={c}
                onEdit={() => setEditingUser(c.username)}
                onReset={() => setResetTarget(c)}
                onToggleStatus={() => setStatusTarget(c)}
              />
            ))}
          </div>
        ) : (
          <div className="glass-panel flex flex-col items-center justify-center gap-2 rounded-2xl py-14 text-center">
            <Users size={32} className="text-slate-300" />
            <p className="text-sm font-semibold text-slate-600">No coordinators match.</p>
            <p className="text-[12px] text-slate-500">
              Adjust the search or {" "}
              <button onClick={() => setEditingUser("new")} className="font-bold text-brand underline">
                add a new coordinator
              </button>.
            </p>
          </div>
        )}
      </div>

      {/* Drawers / dialogs */}
      {editingUser && (
        <CoordinatorFormDrawer
          mode={editingUser === "new" ? "create" : "edit"}
          username={editingUser === "new" ? null : editingUser}
          existingRow={rows.find((r) => r.username === editingUser) || null}
          onClose={() => setEditingUser(null)}
          onSaved={(msg) => setToast({ kind: "ok", msg })}
          onError={(msg) => setToast({ kind: "err", msg })}
          onDone={refresh}
        />
      )}
      {resetTarget && (
        <ResetPasswordDialog
          coord={resetTarget}
          onClose={() => setResetTarget(null)}
          onDone={(msg) => setToast({ kind: "ok", msg })}
          onRefresh={refresh}
        />
      )}
      {statusTarget && (
        <ToggleStatusDialog
          coord={statusTarget}
          onClose={() => setStatusTarget(null)}
          onDone={(msg) => setToast({ kind: "ok", msg })}
          onRefresh={refresh}
        />
      )}

      {toast && <Toast toast={toast} />}
    </>
  );
}

/* ── Row ──────────────────────────────────────────────────────────────────── */
function CoordinatorRow({ coord, onEdit, onReset, onToggleStatus }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const disabled = coord.status === "disabled";
  // .glass-panel sets backdrop-filter, which makes every row its own stacking
  // context — so the menu's own z-index can never lift it above a LATER row.
  // Raising the row itself while its menu is open is what actually fixes it.
  return (
    <div className={`glass-panel glass-hover relative flex items-center gap-4 rounded-2xl p-3 ${menuOpen ? "z-[1000]" : ""} ${disabled ? "opacity-70" : ""}`}>
      <Avatar coord={coord} />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <p className="truncate text-sm font-extrabold tracking-tight text-slate-800">{coord.name}</p>
          {disabled ? (
            <span className="rounded-full bg-slate-200 px-2 py-0.5 text-[10px] font-bold text-slate-600">Disabled</span>
          ) : (
            <span className="flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-bold text-emerald-700 ring-1 ring-emerald-200">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" /> Active
            </span>
          )}
          {coord.mustChangePassword && (
            <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800 ring-1 ring-amber-200">
              Must change password
            </span>
          )}
        </div>
        <div className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11.5px] text-slate-500">
          <span className="font-mono font-semibold text-slate-600">@{coord.username}</span>
          <span>·</span>
          <span className="flex items-center gap-1"><Building2 size={11} /> {coord.constituency || "—"}</span>
          <span>·</span>
          <span className="flex items-center gap-1"><MapPin size={11} /> Ward {coord.homeWard || "—"}</span>
          <span>·</span>
          <span className="font-semibold">{coord.role || "—"}</span>
        </div>
      </div>

      <div className="hidden md:block">
        <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Civic score</p>
        <p className="text-base font-extrabold text-slate-800">{coord.civicScore ?? 0}</p>
      </div>

      <div className="relative">
        <button
          onClick={() => setMenuOpen((m) => !m)}
          onBlur={() => setTimeout(() => setMenuOpen(false), 160)}
          className="glass-panel flex h-9 w-9 items-center justify-center rounded-xl text-slate-500 hover:text-slate-800"
        >
          <MoreVertical size={16} />
        </button>
        {menuOpen && (
          <div className="animate-fade-up absolute right-0 top-full z-20 mt-1 w-52 overflow-hidden rounded-xl bg-white shadow-xl ring-1 ring-slate-200">
            <MenuItem icon={Pencil} label="Edit assignment" onClick={onEdit} />
            <MenuItem icon={KeyRound} label="Reset password" onClick={onReset} />
            <MenuItem
              icon={disabled ? ShieldCheck : ShieldBan}
              label={disabled ? "Re-enable account" : "Disable account"}
              onClick={onToggleStatus}
              tone={disabled ? "text-emerald-700" : "text-rose-600"}
            />
          </div>
        )}
      </div>
    </div>
  );
}
function MenuItem({ icon: Icon, label, onClick, tone = "text-slate-700" }) {
  return (
    <button
      onMouseDown={(e) => e.preventDefault()}
      onClick={onClick}
      className={`flex w-full items-center gap-2.5 px-3 py-2.5 text-[13px] font-semibold hover:bg-slate-50 ${tone}`}
    >
      <Icon size={14} /> {label}
    </button>
  );
}

/* ── Avatar / stat pill / toast ───────────────────────────────────────────── */
function Avatar({ coord }) {
  const initials = coord.initials || initialsFrom(coord.name);
  return (
    <div className="relative shrink-0">
      {coord.avatar ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={coord.avatar} alt="" className="h-11 w-11 rounded-full object-cover ring-2 ring-white shadow-md" />
      ) : (
        <div className="flex h-11 w-11 items-center justify-center rounded-full bg-gradient-to-br from-brand to-brand-dark text-sm font-bold text-white shadow-md ring-2 ring-white">
          {initials}
        </div>
      )}
    </div>
  );
}
function StatPill({ label, value, icon: Icon, tone }) {
  return (
    <div className="glass-panel flex items-center gap-3 rounded-2xl px-4 py-3">
      <Icon size={18} className={tone} />
      <div>
        <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">{label}</p>
        <p className={`text-lg font-extrabold ${tone}`}>{value}</p>
      </div>
    </div>
  );
}
function Toast({ toast }) {
  const ok = toast.kind === "ok";
  return (
    <div className="fixed bottom-6 right-6 z-50 animate-fade-up">
      <div className={`flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold text-white shadow-lg ${ok ? "bg-emerald-600" : "bg-rose-600"}`}>
        {ok ? <CheckCircle2 size={16} /> : <AlertCircle size={16} />} {toast.msg}
      </div>
    </div>
  );
}

/* ── Create / Edit drawer ────────────────────────────────────────────────── */
function CoordinatorFormDrawer({ mode, username, existingRow, onClose, onSaved, onError, onDone }) {
  const editing = mode === "edit";
  const existing = editing ? existingRow : null;
  const [saving, setSaving] = useState(false);

  const [name, setName] = useState(existing?.name || "");
  const [usernameField, setUsernameField] = useState(existing?.username || "");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [role, setRole] = useState(existing?.role || ROLES[0]);
  const [constituency, setConstituency] = useState(existing?.constituency || DEFAULT_CONSTITUENCY);
  const [homeWard, setHomeWard] = useState(existing?.homeWard || "");
  const [mustChange, setMustChange] = useState(true);
  const [copied, setCopied] = useState(false);

  // Suggest a username from the name — only when creating and untouched.
  useEffect(() => {
    if (editing) return;
    if (usernameField) return;
    const first = name.trim().toLowerCase().split(/\s+/)[0];
    if (first) setUsernameField(first);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name]);

  // When constituency changes, reset ward to the first one that AC covers.
  const wardOptions = useMemo(
    () => CHENNAI_AC_MAP[constituency] || [],
    [constituency]
  );
  useEffect(() => {
    if (!homeWard || !wardOptions.includes(homeWard)) {
      setHomeWard(wardOptions[0] || "");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [constituency]);

  function fillTempPassword() {
    const p = generatePassword();
    setPassword(p);
    setShowPassword(true);
  }
  async function copyPassword() {
    if (!password) return;
    try {
      await navigator.clipboard.writeText(password);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch { /* noop */ }
  }

  async function submit(e) {
    e.preventDefault();
    if (!name.trim()) return onError("Name is required");
    if (!editing && !usernameField.trim()) return onError("Username is required");
    if (!editing && password.length < 4) return onError("Password must be at least 4 characters");
    if (saving) return;

    setSaving(true);
    try {
      if (editing) {
        await updateCoordinatorRemote(username, {
          name: name.trim(),
          role,
          constituency,
          homeWard,
          // Only change the password if the admin typed a new one.
          ...(password ? { password, mustChangePassword: mustChange } : {}),
        });
        onSaved(`Updated ${name.trim()}`);
      } else {
        await createCoordinatorRemote({
          name: name.trim(),
          username: usernameField.trim().toLowerCase(),
          password,
          role,
          constituency,
          homeWard,
          mustChangePassword: mustChange,
        });
        onSaved(`Created ${name.trim()} · @${usernameField.trim().toLowerCase()}`);
      }
      onDone?.();
      onClose();
    } catch (err) {
      onError(err.message || "Could not save coordinator");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-slate-900/40 animate-scrim-in" onClick={onClose} />
      <form
        onSubmit={submit}
        className="relative flex h-full w-full max-w-md flex-col overflow-hidden bg-white shadow-2xl animate-drawer-in"
      >
        <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
          <div>
            <h2 className="text-lg font-extrabold tracking-tight text-slate-900">
              {editing ? "Edit coordinator" : "Add coordinator"}
            </h2>
            <p className="text-[11.5px] font-semibold text-slate-500">
              {editing ? `Update @${username}'s assignment` : "Create a new MLA office account"}
            </p>
          </div>
          <button type="button" onClick={onClose} className="text-slate-400 hover:text-slate-700">
            <X size={18} />
          </button>
        </div>

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-6 py-5">
          <Field label="Full name">
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Meera Ravindran"
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand"
              autoFocus={!editing}
            />
          </Field>

          {!editing && (
            <>
              <Field label="Username" hint="Lowercase, no spaces">
                <input
                  value={usernameField}
                  onChange={(e) => setUsernameField(e.target.value.toLowerCase().replace(/\s+/g, ""))}
                  placeholder="meera"
                  className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 font-mono text-sm outline-none focus:border-brand"
                />
              </Field>

              <Field label="Temporary password" hint="Coordinator changes on first login">
                <div className="flex gap-2">
                  <input
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    type={showPassword ? "text" : "password"}
                    placeholder="Set a password or generate one"
                    className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 font-mono text-sm outline-none focus:border-brand"
                  />
                  <button type="button" onClick={fillTempPassword}
                    className="flex shrink-0 items-center gap-1 rounded-xl bg-slate-800 px-3 py-2 text-xs font-bold text-white hover:bg-slate-700">
                    <RefreshCcw size={12} /> Generate
                  </button>
                </div>
                {password && (
                  <div className="mt-2 flex items-center gap-2 rounded-lg bg-amber-50 px-3 py-1.5 text-[11.5px] font-semibold text-amber-800 ring-1 ring-amber-200">
                    <KeyRound size={12} />
                    <span className="flex-1 font-mono">{showPassword ? password : "••••••••"}</span>
                    <button type="button" onClick={() => setShowPassword((s) => !s)} className="underline">
                      {showPassword ? "hide" : "show"}
                    </button>
                    <button type="button" onClick={copyPassword} className="flex items-center gap-1 underline">
                      {copied ? <><Check size={11} /> copied</> : <><Copy size={11} /> copy</>}
                    </button>
                  </div>
                )}
              </Field>
            </>
          )}

          <Field label="Role">
            <select
              value={role}
              onChange={(e) => setRole(e.target.value)}
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand"
            >
              {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
            </select>
          </Field>

          <Field label="Constituency">
            <select
              value={constituency}
              onChange={(e) => setConstituency(e.target.value)}
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand"
            >
              {CONSTITUENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </Field>

          <Field label="Home ward" hint="Coordinator's default ward within their constituency">
            <select
              value={homeWard}
              onChange={(e) => setHomeWard(e.target.value)}
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand"
            >
              {wardOptions.map((w) => <option key={w} value={w}>Ward {w}</option>)}
            </select>
          </Field>

          {!editing && (
            <label className="flex cursor-pointer items-start gap-2.5 rounded-xl border border-slate-200 bg-slate-50 p-3">
              <input
                type="checkbox"
                checked={mustChange}
                onChange={(e) => setMustChange(e.target.checked)}
                className="mt-0.5 h-4 w-4 accent-brand"
              />
              <div>
                <p className="text-[12.5px] font-bold text-slate-800">Force password change on first login</p>
                <p className="text-[11px] text-slate-500">Recommended so the temp password never lingers.</p>
              </div>
            </label>
          )}
        </div>

        <div className="flex items-center justify-end gap-2 border-t border-slate-100 px-6 py-4">
          <button type="button" onClick={onClose} className="rounded-xl px-4 py-2 text-sm font-bold text-slate-600 hover:bg-slate-100">
            Cancel
          </button>
          <button type="submit" disabled={saving} className="flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-brand to-brand-dark px-4 py-2 text-sm font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-60">
            {saving
              ? "Saving…"
              : editing
                ? <><Pencil size={14} className="text-amber-300" /> Save changes</>
                : <><Plus size={14} className="text-amber-300" /> Create coordinator</>}
          </button>
        </div>
      </form>
    </div>
  );
}

function Field({ label, hint, children }) {
  return (
    <label className="block">
      <div className="mb-1 flex items-baseline justify-between">
        <span className="text-[11.5px] font-bold uppercase tracking-wider text-slate-500">{label}</span>
        {hint && <span className="text-[10.5px] font-medium text-slate-400">{hint}</span>}
      </div>
      {children}
    </label>
  );
}

/* ── Reset password dialog ────────────────────────────────────────────────── */
function ResetPasswordDialog({ coord, onClose, onDone, onRefresh }) {
  const [password, setPassword] = useState(generatePassword());
  const [mustChange, setMustChange] = useState(true);
  const [copied, setCopied] = useState(false);
  const [saving, setSaving] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(password);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch { /* noop */ }
  }
  async function confirm() {
    if (saving) return;
    setSaving(true);
    try {
      await updateCoordinatorRemote(coord.username, {
        password,
        mustChangePassword: mustChange,
      });
      onDone(`Password reset for @${coord.username}`);
      onRefresh?.();
      onClose();
    } catch (err) {
      onDone(err.message || "Could not reset password");
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center px-4">
      <div className="absolute inset-0 bg-slate-900/50 animate-scrim-in" onClick={onClose} />
      <div className="relative w-full max-w-md overflow-hidden rounded-3xl bg-white shadow-2xl animate-modal-float">
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3.5">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-amber-100 text-amber-700">
              <KeyRound size={16} />
            </div>
            <div>
              <p className="text-[15px] font-extrabold tracking-tight text-slate-900">Reset password</p>
              <p className="text-[11px] font-semibold text-slate-500">@{coord.username} · {coord.name}</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700">
            <X size={16} />
          </button>
        </div>

        <div className="space-y-3 px-5 py-4">
          <Field label="New temporary password">
            <div className="flex gap-2">
              <input
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 font-mono text-sm outline-none focus:border-brand"
              />
              <button
                type="button"
                onClick={() => setPassword(generatePassword())}
                className="flex shrink-0 items-center gap-1 rounded-xl bg-slate-800 px-3 py-2 text-xs font-bold text-white hover:bg-slate-700"
              >
                <RefreshCcw size={12} /> New
              </button>
              <button
                type="button"
                onClick={copy}
                className="flex shrink-0 items-center gap-1 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700"
              >
                {copied ? <><Check size={12} /> Copied</> : <><Copy size={12} /> Copy</>}
              </button>
            </div>
          </Field>

          <label className="flex cursor-pointer items-start gap-2.5 rounded-xl border border-slate-200 bg-slate-50 p-3">
            <input
              type="checkbox"
              checked={mustChange}
              onChange={(e) => setMustChange(e.target.checked)}
              className="mt-0.5 h-4 w-4 accent-brand"
            />
            <div>
              <p className="text-[12.5px] font-bold text-slate-800">Require change on next login</p>
              <p className="text-[11px] text-slate-500">Coordinator will be prompted to pick a new password.</p>
            </div>
          </label>
        </div>

        <div className="flex justify-end gap-2 border-t border-slate-100 px-5 py-3.5">
          <button onClick={onClose} className="rounded-xl px-4 py-2 text-sm font-bold text-slate-600 hover:bg-slate-100">
            Cancel
          </button>
          <button onClick={confirm} className="rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 px-4 py-2 text-sm font-bold text-white shadow-lg shadow-amber-500/30">
            Reset password
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Toggle status dialog ─────────────────────────────────────────────────── */
function ToggleStatusDialog({ coord, onClose, onDone, onRefresh }) {
  const disabling = coord.status !== "disabled";
  async function confirm() {
    await updateCoordinatorRemote(coord.username, {
      status: disabling ? "disabled" : "active",
    });
    onDone(`${disabling ? "Disabled" : "Re-enabled"} @${coord.username}`);
    onRefresh?.();
    onClose();
  }
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center px-4">
      <div className="absolute inset-0 bg-slate-900/50 animate-scrim-in" onClick={onClose} />
      <div className="relative w-full max-w-sm overflow-hidden rounded-3xl bg-white shadow-2xl animate-modal-float">
        <div className="flex items-center gap-2.5 border-b border-slate-100 px-5 py-3.5">
          <div className={`flex h-9 w-9 items-center justify-center rounded-xl ${disabling ? "bg-rose-100 text-rose-700" : "bg-emerald-100 text-emerald-700"}`}>
            {disabling ? <ShieldBan size={16} /> : <ShieldCheck size={16} />}
          </div>
          <div>
            <p className="text-[15px] font-extrabold tracking-tight text-slate-900">
              {disabling ? "Disable account" : "Re-enable account"}
            </p>
            <p className="text-[11px] font-semibold text-slate-500">@{coord.username} · {coord.name}</p>
          </div>
        </div>
        <div className="px-5 py-4 text-[13px] leading-relaxed text-slate-600">
          {disabling ? (
            <>
              <span className="font-bold text-slate-800">{coord.name}</span> won't be able to sign in until re-enabled.
              Their past actions and grievance history are preserved.
            </>
          ) : (
            <>
              <span className="font-bold text-slate-800">{coord.name}</span> will be able to sign in again with their current password.
            </>
          )}
        </div>
        <div className="flex justify-end gap-2 border-t border-slate-100 px-5 py-3.5">
          <button onClick={onClose} className="rounded-xl px-4 py-2 text-sm font-bold text-slate-600 hover:bg-slate-100">
            Cancel
          </button>
          <button
            onClick={confirm}
            className={`rounded-xl px-4 py-2 text-sm font-bold text-white shadow-lg ${
              disabling
                ? "bg-gradient-to-r from-rose-500 to-rose-600 shadow-rose-500/30"
                : "bg-gradient-to-r from-emerald-500 to-emerald-600 shadow-emerald-500/30"
            }`}
          >
            {disabling ? "Disable" : "Re-enable"}
          </button>
        </div>
      </div>
    </div>
  );
}
