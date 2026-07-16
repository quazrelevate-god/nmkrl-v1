"use client";

/**
 * CoordinatorNav
 * --------------
 * Glass pill nav for the /coordinator app — mirrors the citizen BottomNav
 * (auto-minimize on scroll-down, restore on scroll-up) but the centre "+"
 * opens the post/poll PostComposer instead of the citizen ReportModal.
 */

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, MapPin, Plus, X } from "lucide-react";
import { useCoordinator } from "./CoordinatorProvider";

export default function CoordinatorNav() {
  const pathname = usePathname();
  const { composerOpen, openComposer, closeComposer } = useCoordinator();
  const [min, setMin] = useState(false);

  const lastYByEl = useRef(new WeakMap());

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
      if (y < 16) setMin(false);
      else if (dy > 0) setMin(true);
      else setMin(false);
    };
    document.addEventListener("scroll", onScroll, { capture: true, passive: true });
    return () => document.removeEventListener("scroll", onScroll, { capture: true });
  }, []);

  const isHome = pathname === "/coordinator";
  const isGrievance = pathname.startsWith("/coordinator/grievance");
  const ease = "transition-all duration-[420ms] ease-[cubic-bezier(.22,1,.36,1)]";

  const sideCls = `flex flex-col items-center justify-center rounded-full ${ease} ${
    min ? "w-11 gap-0" : "w-[76px] gap-0.5"
  }`;
  const labelCls = `overflow-hidden text-[10px] font-semibold leading-none ${ease} ${
    min ? "h-0 opacity-0" : "h-3 opacity-100"
  }`;

  return (
    <nav className="pointer-events-none absolute inset-x-0 bottom-0 z-[700] flex justify-center pb-4">
      <div className={`glass-strong pointer-events-auto flex items-center rounded-full shadow-[0_12px_40px_-8px_rgba(15,86,65,0.28)] ${ease} ${min ? "gap-0.5 px-2 py-1.5" : "gap-1 px-2.5 py-2"}`}>
        {/* Community */}
        <Link href="/coordinator" className={`${sideCls} py-1 ${isHome && !composerOpen ? "text-brand" : "text-slate-500"}`}>
          <span className={`flex items-center justify-center rounded-full ${ease} ${min ? "h-8 w-8" : "h-9 w-9"} ${
            isHome && !composerOpen ? "bg-gradient-to-br from-brand/90 via-brand-700/85 to-gold-300/85 text-white shadow-md shadow-brand/20" : ""
          }`}>
            <Home size={min ? 18 : 20} strokeWidth={isHome && !composerOpen ? 2.4 : 1.9} />
          </span>
          <span className={labelCls}>Community</span>
        </Link>

        {/* Create post/poll (+ / ×) */}
        <button
          onClick={composerOpen ? closeComposer : openComposer}
          aria-label={composerOpen ? "Close composer" : "Create post or poll"}
          className={`ease-spring -my-1 flex items-center justify-center rounded-full text-white shadow-lg ${ease} ${
            min ? "h-11 w-11" : "h-14 w-14"
          } ${composerOpen ? "rotate-90 bg-slate-900 ring-1 ring-gold-300/40" : "bg-gradient-to-br from-slate-900 via-slate-950 to-black text-gold-200 ring-1 ring-gold-300/60 shadow-black/40"}`}
        >
          {composerOpen ? <X size={min ? 22 : 26} /> : <Plus size={min ? 24 : 28} />}
        </button>

        {/* Grievance */}
        <Link href="/coordinator/grievance" className={`${sideCls} py-1 ${isGrievance && !composerOpen ? "text-brand" : "text-slate-500"}`}>
          <span className={`flex items-center justify-center rounded-full ${ease} ${min ? "h-8 w-8" : "h-9 w-9"} ${
            isGrievance && !composerOpen ? "bg-gradient-to-br from-brand/90 via-brand-700/85 to-gold-300/85 text-white shadow-md shadow-brand/20" : ""
          }`}>
            <MapPin size={min ? 18 : 20} strokeWidth={isGrievance && !composerOpen ? 2.4 : 1.9} />
          </span>
          <span className={labelCls}>Grievance</span>
        </Link>
      </div>
    </nav>
  );
}
