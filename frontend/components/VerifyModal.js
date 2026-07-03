"use client";

/**
 * VerifyModal
 * -----------
 * Combined: AI summary review + mobile OTP verification.
 * Opens after backend processes the issue. User reviews the AI output,
 * enters their mobile number, verifies OTP (mock default: 1234), then submits.
 */

import { useState } from "react";
import { X, Phone, Shield, Sparkles } from "lucide-react";
import { confirmIssue } from "@/lib/api";

const EXPECTED_OTP = "1234";

export default function VerifyModal({ issue, onVerified, onClose }) {
  const [mobile, setMobile] = useState("");
  const [otp, setOtp]       = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [busy, setBusy]     = useState(false);
  const [error, setError]   = useState(null);

  if (!issue) return null;

  function sendOtp() {
    setError(null);
    if (!/^\d{10}$/.test(mobile)) {
      setError("Enter a valid 10-digit mobile number.");
      return;
    }
    setOtpSent(true);
  }

  async function verify() {
    setError(null);
    if (!/^\d{10}$/.test(mobile)) { setError("Enter a valid 10-digit mobile number."); return; }
    if (!otpSent)                  { setError('Tap "Send OTP" first.');                return; }
    if (otp !== EXPECTED_OTP)      { setError("Invalid OTP. (Hint: use 1234)");        return; }
    setBusy(true);
    try {
      await confirmIssue(issue.id, mobile);
    } catch {}
    setBusy(false);
    onVerified(mobile);
  }

  const highlights = issue.summary_highlights || [];
  const transcript  = issue.transcript || "";

  return (
    <div className="absolute inset-0 z-[600] flex items-end justify-center bg-black/60 p-0">
      <div className="no-scrollbar w-full overflow-y-auto rounded-t-3xl bg-white shadow-2xl" style={{maxHeight:"90%"}}>
        {/* Drag handle */}
        <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300" />

        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-slate-100">
          <div>
            <h3 className="text-base font-bold text-slate-900">Verify & Submit</h3>
            <p className="text-xs text-slate-500">Review AI summary, then confirm your number</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100">
            <X size={18} className="text-slate-400" />
          </button>
        </div>

        <div className="px-5 py-4 space-y-4">
          {/* Issue title + area */}
          <div>
            <p className="font-semibold text-slate-800 leading-tight">{issue.title}</p>
            {issue.area_name && (
              <p className="text-xs text-slate-500 mt-0.5">{issue.area_name}</p>
            )}
          </div>

          {/* AI Summary */}
          <div className="rounded-xl bg-blue-50 border border-blue-100 p-3">
            <div className="flex items-center gap-1.5 mb-2">
              <Sparkles size={14} className="text-brand" />
              <span className="text-xs font-bold text-brand uppercase tracking-wide">AI Summary</span>
            </div>

            {transcript && (
              <p className="text-sm italic text-slate-700 leading-snug mb-2">
                "{transcript}"
              </p>
            )}

            {highlights.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {highlights.map((h, i) => (
                  <span
                    key={i}
                    className="rounded-full bg-white px-2.5 py-0.5 text-[11px] font-medium text-brand ring-1 ring-blue-200"
                  >
                    {h}
                  </span>
                ))}
              </div>
            )}

            {!transcript && highlights.length === 0 && (
              <p className="text-xs text-slate-400">No audio transcription available.</p>
            )}
          </div>

          {/* Mobile number */}
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <Phone size={13} /> Mobile Number
            </label>
            <div className="flex gap-2">
              <span className="flex items-center rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm text-slate-500">
                +91
              </span>
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

          {/* OTP field */}
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
              <p className="mt-1 text-[11px] text-slate-400">
                Demo OTP sent to +91 {mobile}. Use <b>1234</b>.
              </p>
            </div>
          )}

          {error && (
            <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{error}</p>
          )}

          <button
            onClick={verify}
            disabled={busy}
            className="w-full rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg shadow-blue-500/30 disabled:opacity-60"
          >
            {busy ? "Submitting…" : "✓ Verify & Submit"}
          </button>
        </div>
      </div>
    </div>
  );
}
