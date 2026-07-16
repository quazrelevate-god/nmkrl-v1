"use client";

/**
 * UpvoteModal — "Support this grievance"
 * --------------------------------------
 * Lightweight confirmation to add your support to another citizen's public
 * grievance. No name / no OTP — just a fair-use counter (5 supports/day) and an
 * iOS-style swipe to confirm. A full-screen success animation acknowledges it.
 */

import { useEffect, useState } from "react";
import { X, ThumbsUp, ShieldCheck } from "lucide-react";
import SwipeToConfirm from "@/components/SwipeToConfirm";
import SuccessOverlay from "@/components/SuccessOverlay";
import { dailyState, consumeDaily, SUPPORT_LIMIT_KEY } from "@/lib/dailyLimit";

const DAILY_MAX = 5;

export default function UpvoteModal({ issue, onConfirm, onClose }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [showSuccess, setShowSuccess] = useState(false);
  const [resetToken, setResetToken] = useState(0);
  const [limit, setLimit] = useState({ used: 0, remaining: DAILY_MAX, max: DAILY_MAX });

  useEffect(() => { setLimit(dailyState(SUPPORT_LIMIT_KEY, DAILY_MAX)); }, []);

  if (!issue && !showSuccess) return null;

  async function confirm() {
    setError(null);
    // Fair-use counter is display-only for the demo — never blocks support.
    setBusy(true);
    try {
      await onConfirm();
      setLimit(consumeDaily(SUPPORT_LIMIT_KEY, DAILY_MAX));
      setShowSuccess(true);
    } catch (err) {
      setError(err?.message || "Could not add your support. Try again.");
      setResetToken((t) => t + 1);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {issue && !showSuccess && (
        <div className="absolute inset-0 z-[660] flex items-center justify-center px-4 pb-24 pt-6">
          <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />
          <div className="animate-modal-float glass-strong relative z-10 flex w-full flex-col overflow-hidden rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
            <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300/80" />

            <div className="flex items-center justify-between px-5 py-3">
              <div>
                <h3 className="text-base font-bold text-slate-900">Support this grievance</h3>
                <p className="text-xs text-slate-500">Add your voice — no sign-in needed</p>
              </div>
              <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100">
                <X size={18} className="text-slate-400" />
              </button>
            </div>

            <div className="space-y-4 px-5 pb-5">
              {/* Grievance summary */}
              <div className="rounded-2xl bg-slate-50 p-3.5 ring-1 ring-slate-100">
                <p className="text-sm font-semibold leading-tight text-slate-800">{issue.title}</p>
                {issue.area_name && <p className="mt-0.5 text-xs text-slate-500">{issue.area_name}</p>}
                <span className="mt-1.5 inline-flex items-center gap-1 text-xs font-bold text-brand">
                  <ThumbsUp size={12} /> {issue.upvotes} current supports
                </span>
              </div>

              {/* Fair-use counter — display only, never enforced (demo) */}
              <div className="flex items-center gap-2.5 rounded-2xl bg-emerald-50 px-3.5 py-2.5 text-emerald-800 ring-1 ring-emerald-200">
                <ShieldCheck size={16} className="shrink-0" />
                <p className="text-[12.5px] font-semibold leading-snug">
                  <b>{Math.max(0, limit.remaining)}</b> of {DAILY_MAX} supports left today · fair-use limit
                </p>
              </div>

              {error && <p className="rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-600">{error}</p>}

              {/* Swipe to support */}
              <SwipeToConfirm
                label="Swipe to support"
                busyLabel="Adding your support…"
                tone="emerald"
                onConfirm={confirm}
                busy={busy}
                resetToken={resetToken}
              />
            </div>
          </div>
        </div>
      )}

      <SuccessOverlay
        open={showSuccess}
        title="Support Added"
        message="Thanks for amplifying this grievance. The coordinator sees higher-supported issues first."
        onDone={() => { setShowSuccess(false); onClose?.(); }}
      />
    </>
  );
}
