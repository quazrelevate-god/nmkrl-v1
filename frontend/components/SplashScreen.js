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
      {/* TN Government emblem */}
      <div className="mb-6 flex h-28 w-28 items-center justify-center rounded-full bg-white/10 ring-2 ring-white/20">
        <svg viewBox="0 0 100 100" className="h-20 w-20" xmlns="http://www.w3.org/2000/svg">
          {/* Stylised Sarnath Lion Capital / TN emblem shape */}
          <circle cx="50" cy="50" r="46" fill="none" stroke="#c5a44e" strokeWidth="3"/>
          <circle cx="50" cy="50" r="38" fill="none" stroke="#c5a44e" strokeWidth="1.5"/>
          {/* Ashoka Chakra */}
          <circle cx="50" cy="50" r="14" fill="none" stroke="#c5a44e" strokeWidth="2"/>
          {Array.from({ length: 24 }).map((_, i) => {
            const angle = (i * 15 * Math.PI) / 180;
            const x1 = 50 + 10 * Math.cos(angle);
            const y1 = 50 + 10 * Math.sin(angle);
            const x2 = 50 + 14 * Math.cos(angle);
            const y2 = 50 + 14 * Math.sin(angle);
            return <line key={i} x1={x1} y1={y1} x2={x2} y2={y2} stroke="#c5a44e" strokeWidth="1.2"/>;
          })}
          {/* Pillars */}
          <rect x="30" y="22" width="4" height="20" rx="1" fill="#c5a44e"/>
          <rect x="66" y="22" width="4" height="20" rx="1" fill="#c5a44e"/>
          <rect x="30" y="58" width="4" height="20" rx="1" fill="#c5a44e"/>
          <rect x="66" y="58" width="4" height="20" rx="1" fill="#c5a44e"/>
          {/* Top dome */}
          <path d="M38 26 Q50 10 62 26" fill="none" stroke="#c5a44e" strokeWidth="2"/>
          {/* Base */}
          <path d="M28 78 H72" stroke="#c5a44e" strokeWidth="2.5"/>
          <path d="M32 82 H68" stroke="#c5a44e" strokeWidth="1.5"/>
        </svg>
      </div>

      {/* Tamil title */}
      <h1 className="text-3xl font-extrabold tracking-wide" style={{ color: "#c5a44e" }}>
        நம் குறள்
      </h1>
      <p className="mt-2 text-sm font-medium text-white/60 tracking-wider">
        TAMILNADU GOVERNMENT
      </p>

      {/* Subtle tagline */}
      <p className="mt-6 text-xs text-white/40">
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
