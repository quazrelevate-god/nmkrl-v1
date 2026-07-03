"use client";

/**
 * UpvoteModal
 * -----------
 * Gate for upvoting *another citizen's* public grievance. To keep the vote
 * count trustworthy, the upvoter must give their name and verify ownership of
 * a mobile number via OTP (mock default: 1234) before the vote is counted.
 */

import { useState } from "react";
import { X, ThumbsUp, User, Phone, Shield } from "lucide-react";

const EXPECTED_OTP = "1234";

export default function UpvoteModal({ issue, onConfirm, onClose }) {
  const [name, setName]       = useState("");
  const [mobile, setMobile]   = useState("");
  const [otp, setOtp]         = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [busy, setBusy]       = useState(false);
  const [error, setError]     = useState(null);

  if (!issue) return null;

  function sendOtp() {
    setError(null);
    if (name.trim().length < 2)        { setError("Enter your name.");                  return; }
    if (!/^\d{10}$/.test(mobile))      { setError("Enter a valid 10-digit number.");    return; }
    setOtpSent(true);
  }

  async function confirm() {
    setError(null);
    if (name.trim().length < 2)   { setError("Enter your name.");               return; }
    if (!otpSent)                 { setError('Tap "Send OTP" first.');          return; }
    if (otp !== EXPECTED_OTP)     { setError("Invalid OTP. (Hint: use 1234)");  return; }
    setBusy(true);
    try {
      await onConfirm(name.trim());
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="absolute inset-0 z-[660] flex items-center justify-center px-4 pb-24 pt-6">
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />
      <div className="animate-modal-float glass-strong no-scrollbar relative z-10 flex max-h-full w-full flex-col overflow-y-auto rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300/80" />

        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <div>
            <h3 className="text-base font-bold text-slate-900">Support this grievance</h3>
            <p className="text-xs text-slate-500">Verify to add your upvote</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100">
            <X size={18} className="text-slate-400" />
          </button>
        </div>

        <div className="space-y-4 px-5 py-4">
          <div className="rounded-xl bg-slate-50 p-3">
            <p className="text-sm font-semibold leading-tight text-slate-800">{issue.title}</p>
            {issue.area_name && <p className="mt-0.5 text-xs text-slate-500">{issue.area_name}</p>}
            <span className="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-orange-600">
              <ThumbsUp size={12} /> {issue.upvotes} current upvotes
            </span>
          </div>

          {/* Name */}
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <User size={13} /> Your Name
            </label>
            <input
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="e.g. Priya Raman"
              className="w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-brand"
            />
          </div>

          {/* Mobile */}
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <Phone size={13} /> Mobile Number
            </label>
            <div className="flex gap-2">
              <span className="flex items-center rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm text-slate-500">+91</span>
              <input
                inputMode="numeric"
                maxLength={10}
                value={mobile}
                onChange={e => setMobile(e.target.value.replace(/\D/g, ""))}
                placeholder="9876543210"
                className="flex-1 rounded-xl border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-brand"
              />
              <button
                onClick={sendOtp}
                className="shrink-0 rounded-xl bg-slate-800 px-3 py-2.5 text-xs font-semibold text-white"
              >
                {otpSent ? "Resend" : "Send OTP"}
              </button>
            </div>
          </div>

          {/* OTP */}
          {otpSent && (
            <div>
              <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
                <Shield size={13} /> Enter OTP
              </label>
              <input
                inputMode="numeric"
                maxLength={4}
                value={otp}
                onChange={e => setOtp(e.target.value.replace(/\D/g, ""))}
                placeholder="••••"
                className="w-full rounded-xl border border-slate-200 px-3 py-2.5 text-center text-xl tracking-[0.6em] outline-none focus:border-brand"
              />
              <p className="mt-1 text-[11px] text-slate-400">Demo OTP sent to +91 {mobile}. Use <b>1234</b>.</p>
            </div>
          )}

          {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{error}</p>}

          <button
            onClick={confirm}
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-60"
          >
            <ThumbsUp size={15} /> {busy ? "Adding…" : "Verify & Upvote"}
          </button>
        </div>
      </div>
    </div>
  );
}
