"use client";

import Link from "next/link";
import { CheckCircle2, Ticket, MapPin } from "lucide-react";

export default function SuccessModal({ ticket, onClose }) {
  if (!ticket) return null;
  return (
    <div className="absolute inset-0 z-[650] flex items-center justify-center bg-black/50 p-4">
      <div className="w-full rounded-2xl bg-white p-6 text-center shadow-2xl">
        <div className="mx-auto mb-3 flex h-16 w-16 items-center justify-center rounded-full bg-green-100">
          <CheckCircle2 size={36} className="text-green-600" />
        </div>

        <h3 className="text-lg font-extrabold text-slate-900">Grievance Submitted Successfully</h3>
        <p className="mt-1 text-sm text-slate-500">
          Track it anytime in <b>Map &amp; History</b>.
        </p>

        {/* Ticket */}
        <div className="mt-4 rounded-xl border border-dashed border-brand/40 bg-blue-50 p-3">
          <div className="flex items-center justify-center gap-1.5 mb-1">
            <Ticket size={13} className="text-slate-400" />
            <p className="text-[11px] font-medium uppercase tracking-wide text-slate-500">
              Your Tracking Ticket
            </p>
          </div>
          <p className="select-all text-xl font-extrabold tracking-wider text-brand">{ticket}</p>
          <p className="mt-1 text-[10px] text-slate-400">Save this for future tracking reference.</p>
        </div>

        <div className="mt-5 flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 rounded-xl border border-slate-300 py-3 text-sm font-semibold text-slate-700"
          >
            Done
          </button>
          <Link
            href="/map"
            onClick={onClose}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-brand py-3 text-sm font-bold text-white"
          >
            <MapPin size={14} /> View in History
          </Link>
        </div>
      </div>
    </div>
  );
}
