"use client";

/**
 * Coordinator login — username/password against the 4 seeded coordinators.
 * The seed table is shown at the bottom so the demo user can pick credentials.
 * On success we redirect to the coordinator home page (community feed).
 */

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Landmark, User, Lock, LogIn, ArrowRight } from "lucide-react";
import CoordinatorShell from "@/components/coordinator/CoordinatorShell";
import { useCoordinator } from "@/components/coordinator/CoordinatorProvider";
import { COORDINATORS } from "@/lib/coordinators";
import { shortAC } from "@/lib/constituencies";

export default function CoordinatorLoginPage() {
  const router = useRouter();
  const { login } = useCoordinator();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);

  function submit(e) {
    e.preventDefault();
    setError(null);
    const c = login(username, password);
    if (!c) { setError("Invalid username or password."); return; }
    router.replace("/coordinator");
  }

  function quickPick(c) {
    setUsername(c.username);
    setPassword(c.password);
    setError(null);
  }

  return (
    <CoordinatorShell noPad>
      <div className="flex min-h-full flex-col px-6 pb-24 pt-4">
        {/* Brand */}
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-brand to-brand-dark shadow-lg shadow-brand/30">
            <Landmark size={22} className="text-white" />
          </div>
          <div>
            <p className="text-sm font-extrabold leading-tight text-slate-900">Coordinator Console</p>
            <p className="text-[11px] font-medium text-slate-500">Constituency staff portal</p>
          </div>
        </div>

        <div className="mt-8">
          <h1 className="text-2xl font-extrabold leading-tight text-slate-900">Welcome back 👋</h1>
          <p className="mt-1 text-sm text-slate-500">Sign in to manage grievances and community posts.</p>
        </div>

        <form onSubmit={submit} className="mt-6 space-y-3">
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <User size={13} /> Username
            </label>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="e.g. raja"
              autoComplete="username"
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand"
            />
          </div>
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <Lock size={13} /> Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              autoComplete="current-password"
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand"
            />
          </div>
          {error && <p className="rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">{error}</p>}
          <button
            type="submit"
            disabled={!username || !password}
            className="mt-1 flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-brand to-brand-dark py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-50"
          >
            <LogIn size={16} /> Sign In
          </button>
        </form>

        {/* Demo credentials table */}
        <div className="mt-8">
          <p className="mb-2 text-[10px] font-bold uppercase tracking-widest text-slate-400">Demo Coordinators</p>
          <div className="space-y-2">
            {COORDINATORS.map((c) => (
              <button
                key={c.username}
                onClick={() => quickPick(c)}
                className="glass flex w-full items-center gap-3 rounded-2xl p-3 text-left transition hover:-translate-y-0.5"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={c.avatar} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-bold text-slate-800">{c.name}</p>
                  <p className="truncate text-[11px] text-slate-500">{shortAC(c.constituency)} · Ward {c.homeWard}</p>
                  <p className="mt-0.5 flex items-center gap-2 font-mono text-[11px] text-slate-500">
                    <span className="rounded bg-slate-100 px-1.5 py-0.5">{c.username}</span>
                    <span className="rounded bg-slate-100 px-1.5 py-0.5">{c.password}</span>
                  </p>
                </div>
                <ArrowRight size={16} className="shrink-0 text-slate-400" />
              </button>
            ))}
          </div>
          <p className="mt-3 text-center text-[10px] italic text-slate-400">Tap a row to autofill · illustrative PoC auth</p>
        </div>
      </div>
    </CoordinatorShell>
  );
}
