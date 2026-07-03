"use client";

/**
 * BottomNav
 * ---------
 * iOS-style glass pill navigation with three sections:
 *   Community  ·  [ + ]  ·  Map & History
 * The centre button opens the Report pop-up (turns into an ✕ while open).
 */

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, MapPin, Plus, X } from "lucide-react";
import { useReport } from "@/components/ReportProvider";

export default function BottomNav() {
  const pathname = usePathname();
  const { open, openReport, closeReport } = useReport();

  const isCommunity = pathname === "/";
  const isMap = pathname.startsWith("/map");

  return (
    <nav className="pointer-events-none absolute inset-x-0 bottom-0 z-[700] flex justify-center pb-4">
      <div className="glass-strong pointer-events-auto flex items-center gap-1 rounded-full px-2.5 py-2 shadow-[0_12px_40px_-8px_rgba(30,64,175,0.35)]">
        {/* Community */}
        <Link
          href="/"
          className={`flex w-[76px] flex-col items-center gap-0.5 rounded-full py-1.5 text-[10px] font-semibold transition ${
            isCommunity && !open ? "text-brand" : "text-slate-500"
          }`}
        >
          <Home size={20} strokeWidth={isCommunity && !open ? 2.4 : 1.8} />
          Community
        </Link>

        {/* Report (+ / ×) */}
        <button
          onClick={open ? closeReport : openReport}
          aria-label={open ? "Close report" : "Report an issue"}
          className={`ease-spring -my-1 flex h-14 w-14 items-center justify-center rounded-full text-white shadow-lg transition-all duration-300 ${
            open ? "rotate-90 bg-slate-800" : "bg-gradient-to-br from-brand to-brand-dark shadow-brand/40"
          }`}
        >
          {open ? <X size={26} /> : <Plus size={28} />}
          <span className="pointer-events-none absolute -bottom-0.5 translate-y-full text-[10px] font-semibold text-slate-500">
            {open ? "" : ""}
          </span>
        </button>

        {/* Map & History */}
        <Link
          href="/map"
          className={`flex w-[76px] flex-col items-center gap-0.5 rounded-full py-1.5 text-[10px] font-semibold transition ${
            isMap && !open ? "text-brand" : "text-slate-500"
          }`}
        >
          <MapPin size={20} strokeWidth={isMap && !open ? 2.4 : 1.8} />
          Map &amp; History
        </Link>
      </div>
    </nav>
  );
}
