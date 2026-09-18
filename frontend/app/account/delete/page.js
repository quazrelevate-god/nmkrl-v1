"use client";

/**
 * Web account-deletion page for Nam Kural Connect.
 *
 * Google Play asks for a way to request account deletion from the web, not
 * only inside the app. This proves ownership with a one-time SMS code (the same
 * login challenge) and then calls the backend's deletion endpoint, which
 * removes the person's personal data and anonymises the grievances they filed.
 *
 * The page needs no session — deletion is authorised by the code alone.
 */

import { useState } from "react";
import { ShieldCheck, Smartphone, KeyRound, Trash2, CheckCircle2, AlertCircle } from "lucide-react";
import { requestOtp, deleteAccountWithCode } from "@/lib/api";

export default function DeleteAccountPage() {
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [sent, setSent] = useState(false);
  const [devCode, setDevCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [done, setDone] = useState(null); // { deleted, reports_anonymised }

  const digits = phone.replace(/\D/g, "");

  async function sendCode() {
    setError(null);
    if (digits.length < 10) { setError("Enter a valid 10-digit mobile number."); return; }
    setBusy(true);
    try {
      const r = await requestOtp(digits);
      setSent(true);
      setDevCode(r?.dev_otp || "");
    } catch (e) {
      setError(e.message || "Could not send the code. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setError(null);
    if (otp.replace(/\D/g, "").length < 4) { setError("Enter the code sent to your phone."); return; }
    setBusy(true);
    try {
      const r = await deleteAccountWithCode(digits, otp.trim());
      setDone(r);
    } catch (e) {
      setError(e.message || "Deletion failed. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto max-w-md px-5 py-12 sm:py-16">
      <p className="text-[13px] font-bold uppercase tracking-wider text-brand">Nam Kural Connect · நம்குரல்</p>
      <h1 className="mt-1 text-2xl font-extrabold text-slate-900">Delete your account</h1>
      <p className="mt-3 text-[15px] leading-relaxed text-slate-600">
        This permanently removes your name, phone number and voice recordings. The
        grievances you reported stay as anonymous civic records — stripped of anything
        that identifies you — so officials can still fix them. This cannot be undone.
      </p>

      {done ? (
        <div className="mt-8 rounded-2xl border border-emerald-200 bg-emerald-50 p-5">
          <p className="flex items-center gap-2 text-[15px] font-bold text-emerald-800">
            <CheckCircle2 size={18} /> {done.deleted ? "Account deleted" : "Nothing to delete"}
          </p>
          <p className="mt-1.5 text-[14px] text-emerald-800/90">
            {done.deleted
              ? `Your personal data has been removed${done.reports_anonymised ? `, and ${done.reports_anonymised} grievance${done.reports_anonymised === 1 ? "" : "s"} you filed ${done.reports_anonymised === 1 ? "was" : "were"} anonymised` : ""}.`
              : "No account was found for that number."}
          </p>
        </div>
      ) : (
        <div className="mt-8 space-y-4">
          <div>
            <label className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
              <Smartphone size={12} /> Mobile number
            </label>
            <div className="flex gap-2">
              <span className="flex items-center rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm font-semibold text-slate-500">+91</span>
              <input
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                inputMode="numeric"
                placeholder="10-digit number"
                className="w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-sm text-slate-800 outline-none focus:border-brand focus:ring-2 focus:ring-brand/15"
              />
            </div>
          </div>

          {sent && (
            <div>
              <label className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
                <KeyRound size={12} /> Verification code
              </label>
              <input
                value={otp}
                onChange={(e) => setOtp(e.target.value)}
                inputMode="numeric"
                placeholder="6-digit code"
                className="w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-sm tracking-widest text-slate-800 outline-none focus:border-brand focus:ring-2 focus:ring-brand/15"
              />
              <p className="mt-1.5 text-[12px] text-slate-400">
                Sent by SMS to +91 {digits}.{devCode ? ` Demo code: ${devCode}.` : ""}
              </p>
            </div>
          )}

          {error && (
            <p className="flex items-center gap-1.5 rounded-lg bg-rose-50 px-3 py-2 text-[13px] font-medium text-rose-700">
              <AlertCircle size={14} className="shrink-0" /> {error}
            </p>
          )}

          {!sent ? (
            <button
              onClick={sendCode}
              disabled={busy}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-[14px] font-bold text-white transition hover:bg-brand-dark disabled:opacity-50"
            >
              <ShieldCheck size={16} /> {busy ? "Sending…" : "Send verification code"}
            </button>
          ) : (
            <button
              onClick={remove}
              disabled={busy}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-rose-600 py-3 text-[14px] font-bold text-white transition hover:bg-rose-700 disabled:opacity-50"
            >
              <Trash2 size={16} /> {busy ? "Deleting…" : "Permanently delete my account"}
            </button>
          )}
        </div>
      )}

      <p className="mt-8 text-[13px] text-slate-400">
        You can also delete your account inside the app, from Profile → Delete account.
        See our <a className="font-semibold text-brand underline" href="/privacy">Privacy Policy</a>.
      </p>
    </main>
  );
}
