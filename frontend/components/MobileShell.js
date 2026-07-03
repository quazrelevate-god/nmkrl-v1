"use client";

import BottomNav from "./BottomNav";

/**
 * MobileShell
 * -----------
 * Phone-frame wrapper (max-w-md, slate-50 bg, shadow).
 *
 * Props
 *   noPad     – skip horizontal padding (full-bleed screens like map)
 *   splitView – switches <main> to flex-col + overflow-hidden so children
 *               can split the height explicitly (map-history unified view)
 */
export default function MobileShell({ children, noPad = false, splitView = false }) {
  return (
    <div className="flex min-h-screen w-full justify-center">
      <div className="relative flex h-screen w-full max-w-md flex-col overflow-hidden bg-slate-50 shadow-phone">
        {/* Faux status bar */}
        <div className="flex shrink-0 items-center justify-between bg-white px-5 pt-3 pb-1 text-[12px] font-semibold text-slate-800">
          <span>9:41</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
            <span className="tracking-tighter">5G</span>
            <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
          </span>
        </div>

        {/* Screen body — 80px bottom padding for the fixed nav */}
        <main
          className={[
            "no-scrollbar relative flex-1 min-h-0",
            splitView ? "flex flex-col overflow-hidden" : "overflow-y-auto",
            !noPad && !splitView ? "px-4 pt-2 pb-20" : "pb-20",
          ].join(" ")}
        >
          {children}
        </main>

        <BottomNav />
      </div>
    </div>
  );
}
