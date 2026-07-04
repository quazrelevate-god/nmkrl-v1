"use client";

import BottomNav from "./BottomNav";
import ReportModal from "./ReportModal";
import { useReport } from "./ReportProvider";

/**
 * MobileShell
 * -----------
 * Phone-frame wrapper with an iOS glass backdrop. Renders the shared Report
 * pop-up and the glass pill nav.
 *
 * Props
 *   noPad     – skip horizontal padding (full-bleed screens like map)
 *   splitView – <main> becomes flex-col + overflow-hidden so children split
 *               the height explicitly (map-history unified view)
 *   fullBleed – the page owns the whole frame: content scrolls edge-to-edge and
 *               the page provides its own fixed glass bars (community feed). No
 *               status bar / main padding is injected here.
 */
export default function MobileShell({ children, noPad = false, splitView = false, fullBleed = false }) {
  const { open, closeReport } = useReport();

  if (fullBleed) {
    return (
      <div className="flex min-h-screen w-full justify-center">
        <div className="app-bg relative flex h-screen w-full max-w-md flex-col overflow-hidden shadow-phone">
          {children}
          <div className="bottom-blur" aria-hidden />
          <ReportModal open={open} onClose={closeReport} />
          <BottomNav />
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen w-full justify-center">
      <div className="app-bg relative flex h-screen w-full max-w-md flex-col overflow-hidden shadow-phone">
        {/* Faux status bar */}
        <div className="z-20 flex shrink-0 items-center justify-between px-5 pt-3 pb-1 text-[12px] font-semibold text-slate-800">
          <span>9:41</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
            <span className="tracking-tighter">5G</span>
            <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
          </span>
        </div>

        {/* Screen body — no z-index so full-screen overlays (story/comments,
            z-750+) can paint above the nav (z-700) while the report modal
            (z-600) stays below it. */}
        <main
          className={[
            "no-scrollbar relative min-h-0 flex-1",
            splitView ? "flex flex-col overflow-hidden" : "overflow-y-auto",
            // splitView children own the full height and scroll edge-to-edge
            // behind the floating glass nav; only the simple screens get pb.
            !noPad && !splitView ? "px-4 pt-1 pb-28" : splitView ? "" : "pb-28",
          ].join(" ")}
        >
          {children}
        </main>

        <div className="bottom-blur" aria-hidden />
        <ReportModal open={open} onClose={closeReport} />
        <BottomNav />
      </div>
    </div>
  );
}
