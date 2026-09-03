"use client";

/**
 * SchemeCarousel — slow, ambient marquee of active Tamil Nadu welfare schemes.
 *
 * Mobile-first redesign:
 *   • Icon-led cards, minimal text (title + one short benefit line)
 *   • Slow drift (~11 px/s) so it reads as ambient, not distracting
 *   • Pauses on touch/hover; loops seamlessly (track rendered twice)
 *   • Soft edge fade so cards melt into the page rather than hard-clip
 */

import { useEffect, useRef, useState } from "react";
import {
  HeartHandshake, Bus, GraduationCap, Utensils, Rocket,
  Stethoscope, BookOpen, Handshake, Sparkles,
} from "lucide-react";

const ICON = {
  HeartHandshake, Bus, GraduationCap, Utensils, Rocket,
  Stethoscope, BookOpen, Handshake,
};

// Soft tinted accents per scheme — keeps the strip calm but not monotone.
const TONE = {
  rose:   { bg: "bg-rose-50",    ring: "ring-rose-100",    icon: "text-rose-500" },
  teal:   { bg: "bg-brand/10",   ring: "ring-brand/15",    icon: "text-brand" },
  indigo: { bg: "bg-indigo-50",  ring: "ring-indigo-100",  icon: "text-indigo-500" },
  amber:  { bg: "bg-amber-50",   ring: "ring-amber-100",   icon: "text-amber-600" },
  green:  { bg: "bg-emerald-50", ring: "ring-emerald-100", icon: "text-emerald-600" },
};

export default function SchemeCarousel({ schemes }) {
  const [paused, setPaused] = useState(false);
  const trackRef = useRef(null);

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;
    let raf;
    let last = performance.now();
    // Track position as a float — reading el.scrollLeft back each frame rounds
    // to an integer, so sub-pixel increments (~0.18px/frame) would never
    // accumulate past zero. Keeping our own accumulator fixes the drift.
    let pos = el.scrollLeft;
    const speed = 11; // px/sec — slow, ambient drift
    function tick(now) {
      const dt = (now - last) / 1000;
      last = now;
      if (!paused) {
        const half = el.scrollWidth / 2;
        pos += speed * dt;
        if (half > 0 && pos >= half) pos -= half;
        el.scrollLeft = pos;
      }
      raf = requestAnimationFrame(tick);
    }
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [paused]);

  const doubled = [...schemes, ...schemes];

  return (
    <div
      className="-mx-4 overflow-hidden"
      style={{
        WebkitMaskImage:
          "linear-gradient(to right, transparent, #000 5%, #000 95%, transparent)",
        maskImage:
          "linear-gradient(to right, transparent, #000 5%, #000 95%, transparent)",
      }}
      onTouchStart={() => setPaused(true)}
      onTouchEnd={() => setPaused(false)}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
    >
      <div ref={trackRef} className="no-scrollbar flex gap-2.5 overflow-x-auto px-4 py-1">
        {doubled.map((s, i) => <SchemeCard key={`${s.id}-${i}`} scheme={s} />)}
      </div>
    </div>
  );
}

function SchemeCard({ scheme }) {
  const Icon = ICON[scheme.icon] || Sparkles;
  const tone = TONE[scheme.tone] || TONE.teal;
  return (
    <div className="glass-strong flex min-w-[168px] max-w-[168px] shrink-0 flex-col rounded-2xl p-3 shadow-sm">
      <div className="flex items-center justify-between">
        <span className={`flex h-9 w-9 items-center justify-center rounded-xl ring-1 ${tone.bg} ${tone.ring} ${tone.icon}`}>
          <Icon size={17} strokeWidth={1.9} />
        </span>
        <span className="flex items-center gap-1 rounded-full bg-emerald-50 px-1.5 py-0.5 text-[8.5px] font-bold uppercase tracking-wide text-emerald-600">
          <span className="h-1 w-1 rounded-full bg-emerald-500" /> Active
        </span>
      </div>
      <p className="mt-2.5 line-clamp-2 text-[12.5px] font-extrabold leading-tight tracking-tight text-slate-900">
        {scheme.title}
      </p>
      <p className="mt-1 line-clamp-1 text-[10.5px] font-semibold text-slate-500">
        {scheme.benefit}
      </p>
    </div>
  );
}
