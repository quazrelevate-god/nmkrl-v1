"use client";

/**
 * CoordinatorShell
 * ----------------
 * Phone-frame wrapper for the /coordinator app. Mirrors citizen MobileShell:
 *   fullBleed=true  → community page (fixed-header full-bleed feed)
 *   splitView=true  → grievance page (map+list stacked, edge-to-edge scroll)
 *   default         → padded body screens (login)
 * Renders the coordinator PostComposer + CoordinatorNav.
 */

import CoordinatorNav from "./CoordinatorNav";
import PostComposer from "./PostComposer";
import { useCoordinator } from "./CoordinatorProvider";

export default function CoordinatorShell({ children, noPad = false, splitView = false, fullBleed = false }) {
  const { composerOpen, closeComposer } = useCoordinator();

  if (fullBleed) {
    return (
      <div className="flex min-h-screen w-full justify-center">
        <div className="app-bg relative flex h-screen w-full max-w-md flex-col overflow-hidden shadow-phone">
          {children}
          <div className="bottom-blur" aria-hidden />
          <PostComposer open={composerOpen} onClose={closeComposer} />
          <CoordinatorNav />
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen w-full justify-center">
      <div className="app-bg relative flex h-screen w-full max-w-md flex-col overflow-hidden shadow-phone">
        {/* Status bar */}
        <div className="z-20 flex shrink-0 items-center justify-between px-5 pt-3 pb-1 text-[12px] font-semibold text-slate-800">
          <span>9:41</span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block h-2.5 w-2.5 rounded-full bg-slate-700" />
            <span className="tracking-tighter">5G</span>
            <span className="inline-block h-2.5 w-5 rounded-sm border border-slate-700" />
          </span>
        </div>
        <main
          className={[
            "no-scrollbar relative min-h-0 flex-1",
            splitView ? "flex flex-col overflow-hidden" : "overflow-y-auto",
            !noPad && !splitView ? "px-4 pt-1 pb-28" : splitView ? "" : "pb-28",
          ].join(" ")}
        >
          {children}
        </main>
        <div className="bottom-blur" aria-hidden />
        <PostComposer open={composerOpen} onClose={closeComposer} />
        <CoordinatorNav />
      </div>
    </div>
  );
}
