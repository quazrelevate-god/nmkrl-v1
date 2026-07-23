"use client";

/**
 * BottomNav
 * ---------
 * Phase-1 pilot: the app has a single citizen screen (the map home), so the
 * old glass pill (Community · [+] · Map) is gone. All that remains is the
 * floating "+" action button that opens the Report pop-up (turns into an ✕
 * while open).
 */

import { Plus, X } from "lucide-react";
import { useReport } from "@/components/ReportProvider";

export default function BottomNav() {
  const { open, openReport, closeReport } = useReport();
  const ease = "transition-all duration-[420ms] ease-[cubic-bezier(.22,1,.36,1)]";

  return (
    <nav className="pointer-events-none absolute inset-x-0 bottom-0 z-[700] flex justify-center pb-6">
      <button
        onClick={open ? closeReport : openReport}
        aria-label={open ? "Close report" : "Report an issue"}
        className={`ease-spring pointer-events-auto flex h-16 w-16 items-center justify-center rounded-full text-white shadow-[0_12px_40px_-6px_rgba(26,53,86,0.45)] ${ease} ${
          open ? "rotate-90 bg-slate-800" : "bg-gradient-to-br from-brand to-brand-dark shadow-brand/40"
        }`}
      >
        {open ? <X size={30} /> : <Plus size={32} />}
      </button>
    </nav>
  );
}
