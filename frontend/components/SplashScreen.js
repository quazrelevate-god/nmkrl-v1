"use client";

import { useEffect, useState } from "react";

export default function SplashScreen({ onDone }) {
  const [fadeOut, setFadeOut] = useState(false);

  useEffect(() => {
    const t1 = setTimeout(() => setFadeOut(true), 1400);
    const t2 = setTimeout(() => onDone(), 1800);
    return () => { clearTimeout(t1); clearTimeout(t2); };
  }, [onDone]);

  return (
    <div
      className={`fixed inset-0 z-[9999] flex flex-col items-center justify-center transition-opacity duration-400 ${
        fadeOut ? "opacity-0" : "opacity-100"
      }`}
      style={{ background: "linear-gradient(160deg, #1e3a5f 0%, #0f1f36 100%)" }}
    >
      {/* Wordmark: Tamil title with the signal-wave mark radiating from
          the top-right, exactly as on the cover reference. */}
      <div className="relative flex items-end gap-3">
        <h1
          className="text-[56px] font-extrabold leading-[0.95] tracking-tight"
          style={{ color: "#f2e4bc" }}
        >
          நம் குரல்
        </h1>

        {/* Signal-wave mark: gold dot with three concentric arcs opening
            up-and-right, sitting above the last consonant. */}
        <svg
          viewBox="0 0 64 64"
          className="absolute -right-8 top-[-6px] h-10 w-10"
          xmlns="http://www.w3.org/2000/svg"
          aria-hidden
        >
          <circle cx="18" cy="46" r="4.5" fill="#c8a04a" />
          <path d="M18 34 A22 22 0 0 1 40 56"      fill="none" stroke="#c8a04a" strokeWidth="3"  strokeLinecap="round" />
          <path d="M18 24 A32 32 0 0 1 50 56"      fill="none" stroke="#c8a04a" strokeWidth="2.5" strokeLinecap="round" />
          <path d="M18 14 A42 42 0 0 1 60 56"      fill="none" stroke="#c8a04a" strokeWidth="2"   strokeLinecap="round" />
        </svg>
      </div>

      {/* Gold ornamental underline with centred diamond */}
      <div className="mt-4 flex items-center gap-2" aria-hidden>
        <span className="h-px w-16 bg-gold-300/80" />
        <span className="h-1.5 w-1.5 rotate-45 bg-gold-300" />
        <span className="h-px w-16 bg-gold-300/80" />
      </div>

      <p className="mt-6 text-[11px] font-medium tracking-[0.28em] text-white/55">
        TAMIL NADU GOVERNMENT
      </p>

      <p className="mt-2 text-xs text-white/40">
        Civic Grievance Redressal Platform
      </p>

      {/* Loading dots */}
      <div className="mt-8 flex gap-1.5">
        {[0, 1, 2].map(i => (
          <span
            key={i}
            className="h-2 w-2 rounded-full bg-white/40"
            style={{
              animation: "splash-dot 1s ease-in-out infinite",
              animationDelay: `${i * 0.2}s`,
            }}
          />
        ))}
      </div>
    </div>
  );
}
