"use client";

/**
 * BottomNav
 * ---------
 * iOS-style glass pill navigation with three sections:
 *   Community  ·  [ + ]  ·  Map & History
 * The centre button opens the Report pop-up (turns into an ✕ while open).
 *
 * The pill MINIMISES (labels collapse, buttons shrink) as the user scrolls
 * down, and springs back to full size when they scroll up — detected via a
 * capture-phase scroll listener so it works for whichever inner container is
 * scrolling (community feed or map history list).
 */

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, MapPin, Plus, X } from "lucide-react";
import { useReport } from "@/components/ReportProvider";

export default function BottomNav() {
  const pathname = usePathname();
  const { open, openReport, closeReport } = useReport();
  const [min, setMin] = useState(false);

  // Track each scroll container's last position independently, so a stray
  // scroll on one element (e.g. the horizontal stories strip) can't clobber
  // the direction baseline of the container the user is actually reading.
  const lastYByEl = useRef(new WeakMap());

  // Reset to full size whenever the page changes.
  useEffect(() => { setMin(false); }, [pathname]);

  useEffect(() => {
    const onScroll = (e) => {
      const el = e.target;
      if (!el) return;
      const y = (el === document || el === document.documentElement)
        ? document.documentElement.scrollTop
        : (el.scrollTop ?? 0);
      const map = lastYByEl.current;
      const prev = map.has(el) ? map.get(el) : y;
      map.set(el, y);
      const dy = y - prev;
      if (Math.abs(dy) < 6) return;
      if (y < 16) setMin(false);        // near the top → always full
      else if (dy > 0) setMin(true);    // scrolling down → minimise
      else setMin(false);               // scrolling up → restore
    };
    document.addEventListener("scroll", onScroll, { capture: true, passive: true });
    return () => document.removeEventListener("scroll", onScroll, { capture: true });
  }, []);

  const isCommunity = pathname === "/";
  const isMap = pathname.startsWith("/map");
  const ease = "transition-all duration-[420ms] ease-[cubic-bezier(.22,1,.36,1)]";

  const sideCls = `flex flex-col items-center justify-center rounded-full ${ease} ${
    min ? "w-11 gap-0" : "w-[76px] gap-0.5"
  }`;
  const labelCls = `overflow-hidden text-[10px] font-semibold leading-none ${ease} ${
    min ? "h-0 opacity-0" : "h-3 opacity-100"
  }`;

  return (
    <nav className="pointer-events-none absolute inset-x-0 bottom-0 z-[700] flex justify-center pb-4">
      <div
        className={`glass-strong pointer-events-auto flex items-center rounded-full shadow-[0_12px_40px_-8px_rgba(51,65,85,0.28)] ${ease} ${
          min ? "gap-0.5 px-2 py-1.5" : "gap-1 px-2.5 py-2"
        }`}
      >
        {/* Community */}
        <Link href="/" className={`${sideCls} py-1.5 ${isCommunity && !open ? "text-brand" : "text-slate-500"}`}>
          <Home size={min ? 19 : 20} strokeWidth={isCommunity && !open ? 2.4 : 1.8} />
          <span className={labelCls}>Community</span>
        </Link>

        {/* Report (+ / ×) */}
        <button
          onClick={open ? closeReport : openReport}
          aria-label={open ? "Close report" : "Report an issue"}
          className={`ease-spring -my-1 flex items-center justify-center rounded-full text-white shadow-lg ${ease} ${
            min ? "h-11 w-11" : "h-14 w-14"
          } ${open ? "rotate-90 bg-slate-800" : "bg-gradient-to-br from-brand to-brand-dark shadow-brand/40"}`}
        >
          {open ? <X size={min ? 22 : 26} /> : <Plus size={min ? 24 : 28} />}
        </button>

        {/* Map & History */}
        <Link href="/map" className={`${sideCls} py-1.5 ${isMap && !open ? "text-brand" : "text-slate-500"}`}>
          <MapPin size={min ? 19 : 20} strokeWidth={isMap && !open ? 2.4 : 1.8} />
          <span className={labelCls}>Map &amp; History</span>
        </Link>
      </div>
    </nav>
  );
}
