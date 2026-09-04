"use client";

/**
 * /admin/login — the door to the staff portal.
 *
 * Everything under /admin creates and edits real records: coordinator
 * accounts, password resets, grievance status. It was all reachable by anyone
 * who typed the URL. This is the gate; the backend verifies the token it
 * hands out on every /api/admin/* request, so the console cannot be talked
 * past by clearing browser storage.
 */

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Lock, Loader2, AlertCircle } from "lucide-react";
import { adminLogin, getAdminToken } from "@/lib/adminAuth";

export default function AdminLoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  // Already signed in — skip the form.
  useEffect(() => {
    if (getAdminToken()) router.replace("/admin");
  }, [router]);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await adminLogin(username.trim(), password);
      router.replace("/admin");
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 px-5">
      <form
        onSubmit={submit}
        className="w-full max-w-sm rounded-3xl bg-white/95 p-8 shadow-2xl ring-1 ring-white/20"
      >
        <div className="mb-6 flex flex-col items-center text-center">
          <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-brand/10 text-brand">
            <Lock size={22} />
          </div>
          <h1 className="text-xl font-extrabold tracking-tight text-slate-900">
            Petition Management
          </h1>
          <p className="mt-1 text-[11px] font-semibold uppercase tracking-wider text-slate-400">
            MLA Office · Staff portal
          </p>
        </div>

        <label className="mb-1 block text-[11px] font-bold uppercase tracking-wide text-slate-500">
          Username
        </label>
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          autoComplete="username"
          autoFocus
          className="mb-4 w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20"
        />

        <label className="mb-1 block text-[11px] font-bold uppercase tracking-wide text-slate-500">
          Password
        </label>
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          autoComplete="current-password"
          className="mb-5 w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20"
        />

        {error && (
          <p className="mb-4 flex items-start gap-1.5 rounded-xl bg-rose-50 px-3 py-2 text-[12px] font-semibold text-rose-700">
            <AlertCircle size={14} className="mt-px shrink-0" /> {error}
          </p>
        )}

        <button
          type="submit"
          disabled={busy || !username || !password}
          className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-brand to-brand-dark py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 transition hover:-translate-y-px disabled:opacity-50 disabled:hover:translate-y-0"
        >
          {busy ? <Loader2 size={16} className="animate-spin" /> : null}
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}
