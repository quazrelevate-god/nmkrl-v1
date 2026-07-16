"use client";

/**
 * Citizen login — minimal Aadhaar/Voter-ID + OTP sign-in for the Namm Kural
 * citizen app. Illustrative PoC auth: no real verification. A giant faded
 * நம்குரல் wordmark sits behind the form as a backdrop. The "Continue as"
 * demo pill at the bottom autofills every field and signs in with one tap.
 *
 * On success we set localStorage `nk_citizen_authed` and land on the citizen
 * feed (which is gated on that flag).
 */

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  User, IdCard, Vote, Smartphone, Lock, ShieldCheck, KeyRound, LogIn,
  ArrowRight, CheckCircle2, RefreshCw,
} from "lucide-react";

const DEMO = {
  name: "Raj Kumar",
  idType: "aadhaar",
  id: "4271 8890 1123",
  mobile: "98840 12345",
  password: "raj@2026",
  otp: "246813",
};

/* Signal-wave brand mark (matches the splash / favicon). */
function WaveMark({ className, color = "#c8a04a" }) {
  return (
    <svg viewBox="0 0 64 64" className={className} style={{ color }} aria-hidden>
      <circle cx="18" cy="46" r="4.5" fill="currentColor" />
      <path d="M18 34 A22 22 0 0 1 40 56" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      <path d="M18 24 A32 32 0 0 1 50 56" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M18 14 A42 42 0 0 1 60 56" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function Field({ icon: Icon, label, children }) {
  return (
    <div>
      <label className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
        <Icon size={12} /> {label}
      </label>
      {children}
    </div>
  );
}

const inputCls =
  "w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-sm text-slate-800 outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/15";

export default function CitizenLoginPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [idType, setIdType] = useState("aadhaar"); // aadhaar | voter
  const [idValue, setIdValue] = useState("");
  const [mobile, setMobile] = useState("");
  const [password, setPassword] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [error, setError] = useState(null);

  const mobileDigits = mobile.replace(/\D/g, "");
  const verified = otpSent && otp.replace(/\D/g, "").length === 6;
  const canLogin = name.trim() && idValue.trim() && mobileDigits.length >= 10 && password && verified;

  function sendOtp() {
    if (mobileDigits.length < 10) { setError("Enter the Aadhaar-linked mobile number first."); return; }
    setError(null);
    setOtpSent(true);
  }

  function finishLogin() {
    localStorage.setItem("nk_citizen_authed", "1");
    localStorage.setItem("nk_citizen_name", (name || DEMO.name).trim());
    router.replace("/");
  }

  function submit(e) {
    e.preventDefault();
    if (!canLogin) { setError("Complete every field and verify the OTP to continue."); return; }
    finishLogin();
  }

  // Demo pill: fill every field + sign in with one tap.
  function demoLogin() {
    setName(DEMO.name);
    setIdType(DEMO.idType);
    setIdValue(DEMO.id);
    setMobile(DEMO.mobile);
    setPassword(DEMO.password);
    setOtpSent(true);
    setOtp(DEMO.otp);
    setError(null);
    setTimeout(finishLogin, 400);
  }

  return (
    <div className="flex min-h-screen w-full justify-center">
      <div
        className="relative flex h-screen w-full max-w-md flex-col overflow-hidden shadow-phone"
        style={{ background: "linear-gradient(165deg, #1e3a5f 0%, #12233f 55%, #0b1626 100%)" }}
      >
        {/* status bar */}
        <div className="relative z-10 flex items-center justify-between px-5 pt-3 pb-1 text-[12px] font-semibold text-white/80">
          <span>9:41</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-white/70" />
            <span className="tracking-tighter">5G</span>
            <span className="inline-block h-2.5 w-5 rounded-sm border border-white/70" />
          </span>
        </div>

        {/* scrollable content */}
        <div className="no-scrollbar relative z-10 flex-1 overflow-y-auto px-6 pb-8">
          {/* Brand lockup */}
          <div className="mt-8 flex flex-col items-center text-center">
            <div className="relative flex items-end">
              <span className="text-[34px] font-black leading-none tracking-tight text-[#eadfbf]">நம்குரல்</span>
              <WaveMark className="absolute -right-6 -top-2 h-6 w-6" />
            </div>
            <p className="mt-3 text-[11px] font-semibold uppercase tracking-[0.28em] text-white/50">
              Citizen Sign In
            </p>
          </div>

          {/* Form card */}
          <form
            onSubmit={submit}
            className="mt-7 space-y-4 rounded-3xl bg-white/95 p-5 shadow-2xl ring-1 ring-white/40 backdrop-blur"
          >
            <Field icon={User} label="Full name">
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="As per your ID" className={inputCls} />
            </Field>

            {/* ID type toggle + value */}
            <Field icon={idType === "aadhaar" ? IdCard : Vote} label="Identity">
              <div className="mb-2 grid grid-cols-2 gap-1 rounded-xl bg-slate-100 p-1">
                {[
                  { k: "aadhaar", label: "Aadhaar", Icon: IdCard },
                  { k: "voter", label: "Voter ID", Icon: Vote },
                ].map(({ k, label, Icon }) => (
                  <button
                    key={k}
                    type="button"
                    onClick={() => setIdType(k)}
                    className={`flex items-center justify-center gap-1.5 rounded-lg py-1.5 text-[12px] font-bold transition ${
                      idType === k ? "bg-white text-brand shadow-sm" : "text-slate-500"
                    }`}
                  >
                    <Icon size={13} /> {label}
                  </button>
                ))}
              </div>
              <input
                value={idValue}
                onChange={(e) => setIdValue(e.target.value)}
                placeholder={idType === "aadhaar" ? "XXXX XXXX XXXX" : "ABC1234567"}
                inputMode={idType === "aadhaar" ? "numeric" : "text"}
                className={inputCls}
              />
            </Field>

            {/* Mobile + Send OTP */}
            <Field icon={Smartphone} label="Aadhaar-linked mobile">
              <div className="flex gap-2">
                <div className="flex items-center rounded-xl border border-slate-200 bg-slate-50 px-2.5 text-sm font-semibold text-slate-500">
                  +91
                </div>
                <input
                  value={mobile}
                  onChange={(e) => setMobile(e.target.value)}
                  placeholder="98xxx xxxxx"
                  inputMode="numeric"
                  className={`${inputCls} flex-1`}
                />
                <button
                  type="button"
                  onClick={sendOtp}
                  disabled={mobileDigits.length < 10}
                  className="shrink-0 rounded-xl bg-brand px-3 text-[12px] font-bold text-white transition disabled:opacity-40"
                >
                  {otpSent ? "Resend" : "Send OTP"}
                </button>
              </div>
            </Field>

            {/* OTP (revealed after send) */}
            {otpSent && (
              <Field icon={KeyRound} label="Enter OTP">
                <div className="relative">
                  <input
                    value={otp}
                    onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
                    placeholder="••••••"
                    inputMode="numeric"
                    className={`${inputCls} pr-10 text-center text-lg font-bold tracking-[0.5em]`}
                  />
                  {verified && (
                    <CheckCircle2 size={20} className="absolute right-3 top-1/2 -translate-y-1/2 fill-emerald-500 text-white" />
                  )}
                </div>
                <p className="mt-1.5 flex items-center gap-1 text-[11px] text-slate-500">
                  <RefreshCw size={10} /> OTP sent to +91 {mobile || "98xxx xxxxx"} · demo code <b className="text-slate-700">246813</b>
                </p>
              </Field>
            )}

            <Field icon={Lock} label="Password">
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className={inputCls}
              />
            </Field>

            {error && <p className="rounded-lg bg-rose-50 px-3 py-2 text-xs font-medium text-rose-600">{error}</p>}

            <button
              type="submit"
              disabled={!canLogin}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-brand to-brand-dark py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 transition disabled:opacity-45"
            >
              <LogIn size={16} /> Login
            </button>

            <p className="flex items-center justify-center gap-1.5 text-[10px] font-medium text-slate-400">
              <ShieldCheck size={11} className="text-emerald-500" /> Secured by Aadhaar e-KYC · Illustrative PoC
            </p>
          </form>

          {/* Demo profile pill — one-tap fill + login */}
          <button
            onClick={demoLogin}
            className="group mt-5 flex w-full items-center gap-3 rounded-2xl bg-white/10 p-3 text-left ring-1 ring-white/15 backdrop-blur transition hover:bg-white/15"
          >
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-gradient-to-br from-amber-300 via-yellow-400 to-amber-500 text-sm font-black text-brand-dark ring-2 ring-white/30">
              RK
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-bold text-white">Continue as Raj Kumar</span>
              <span className="block text-[11px] text-white/60">Demo citizen · autofills every field &amp; signs in</span>
            </span>
            <ArrowRight size={18} className="shrink-0 text-gold-200 transition group-hover:translate-x-0.5" />
          </button>

          <p className="mt-3 text-center text-[11px] text-white/40">
            New to Namm Kural? <span className="font-semibold text-gold-200">Register with Aadhaar</span>
          </p>
        </div>
      </div>
    </div>
  );
}
