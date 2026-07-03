"use client";

import Link from "next/link";
import { CheckCircle2, Ticket, MapPin, Sparkles } from "lucide-react";

export default function SuccessModal({ ticket, onClose }) {
  if (!ticket) return null;
  return (
    <div className="absolute inset-0 z-[660] flex items-center justify-center px-5 pb-24 pt-6">
      {/* Blurred scrim */}
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />

      {/* Floating iOS glass card */}
      <div className="animate-modal-float glass-strong relative z-10 w-full overflow-hidden rounded-[30px] p-6 text-center shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        {/* Success check with halo */}
        <div className="relative mx-auto mb-4 flex h-20 w-20 items-center justify-center">
          <span className="absolute inset-0 rounded-full bg-green-400/30 blur-md" />
          <div className="relative flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-green-400 to-emerald-600 shadow-lg shadow-emerald-500/30">
            <CheckCircle2 size={34} className="text-white" strokeWidth={2.4} />
          </div>
        </div>

        <h3 className="text-xl font-extrabold text-slate-900">Grievance Submitted</h3>
        <p className="mt-1 text-sm text-slate-500">
          Track it anytime in <b className="text-slate-700">Map &amp; History</b>.
        </p>

        {/* Ticket */}
        <div className="mt-5 rounded-2xl border border-brand/15 bg-brand-50/70 p-4">
          <div className="mb-1 flex items-center justify-center gap-1.5">
            <Ticket size={13} className="text-brand" />
            <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">Your Tracking Ticket</p>
          </div>
          <p className="select-all text-2xl font-black tracking-wider text-brand">{ticket}</p>
          <p className="mt-1 flex items-center justify-center gap-1 text-[10px] text-slate-400">
            <Sparkles size={10} /> Save this for future reference
          </p>
        </div>

        <div className="mt-5 flex gap-2.5">
          <button
            onClick={onClose}
            className="flex-1 rounded-2xl bg-white/70 py-3 text-sm font-semibold text-slate-700 ring-1 ring-slate-200 hover:bg-white"
          >
            Done
          </button>
          <Link
            href="/map"
            onClick={onClose}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-2xl bg-gradient-to-br from-brand to-brand-dark py-3 text-sm font-bold text-white shadow-lg shadow-brand/30"
          >
            <MapPin size={14} /> View in History
          </Link>
        </div>
      </div>
    </div>
  );
}
