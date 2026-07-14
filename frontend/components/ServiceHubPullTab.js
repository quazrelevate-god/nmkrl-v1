"use client";

/**
 * ServiceHubPullTab
 * -----------------
 * Right-edge pull tab that reveals the Service Hub page inline as the user
 * drags. Keeps the citizen nav pill symmetric (Community · [+] · Map) while
 * still giving one-hand quick access to /service-hub.
 *
 *   • Tap the tab                → navigate straight to /service-hub
 *   • Drag left                  → an iframe of /service-hub follows the finger
 *     (peek preview)
 *   • Release past the threshold → snap open (navigate) so the page becomes
 *     the actual route
 *   • Release before threshold   → snap back, no navigation
 *
 * Hidden on the /service-hub route itself so it never overlaps its own page.
 */

import { useEffect, useRef, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { Sparkles, ChevronLeft } from "lucide-react";

const COMMIT_RATIO = 0.35;          // release past 35% width → open the hub
const TAB_W = 34;                    // px — visible width of the tab
const DRAG_ACTIVATE_PX = 6;          // finger travel that counts as a drag (not tap)

export default function ServiceHubPullTab() {
  const router = useRouter();
  const pathname = usePathname();
  const [pull, setPull] = useState(0);          // 0..1 progress
  const [dragging, setDragging] = useState(false);
  const [committing, setCommitting] = useState(false);
  const [width, setWidth] = useState(375);
  const rootRef = useRef(null);
  const startX = useRef(null);
  const draggedRef = useRef(false);

  useEffect(() => {
    const measure = () => setWidth(rootRef.current?.parentElement?.offsetWidth || 375);
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  // Reset any lingering pull on route change (e.g. after commit finishes).
  useEffect(() => { setPull(0); setCommitting(false); }, [pathname]);

  // Hide on service-hub itself.
  if (pathname?.startsWith("/service-hub")) return null;

  function onDown(clientX, target, pointerId) {
    startX.current = clientX;
    draggedRef.current = false;
    setDragging(true);
    try { target.setPointerCapture(pointerId); } catch { /* ignore */ }
  }
  function onMove(clientX) {
    if (startX.current == null) return;
    const dx = startX.current - clientX;         // leftward drag = positive
    if (dx > DRAG_ACTIVATE_PX) draggedRef.current = true;
    if (dx < 0) { setPull(0); return; }
    setPull(Math.min(1, dx / width));
  }
  function onUp() {
    setDragging(false);
    startX.current = null;

    // Tap (no drag) → navigate directly.
    if (!draggedRef.current) {
      setCommitting(true);
      setPull(1);
      setTimeout(() => router.push("/service-hub"), 220);
      return;
    }

    // Drag release: commit if past threshold, else snap back.
    if (pull >= COMMIT_RATIO) {
      setCommitting(true);
      setPull(1);
      setTimeout(() => router.push("/service-hub"), 220);
    } else {
      setPull(0);
    }
  }

  const panelTranslatePct = (1 - pull) * 100;              // 100 = fully hidden right
  const tabTranslatePx = pull * (width - TAB_W - 4);       // slide with the panel edge
  const transition = dragging ? "none" : "transform .34s cubic-bezier(.22,1,.36,1), opacity .34s ease";
  const showPreview = pull > 0 || committing;

  return (
    <div ref={rootRef} className="pointer-events-none absolute inset-0 z-[720]">
      {/* Dim scrim behind the peek */}
      {showPreview && (
        <div
          className="absolute inset-0 bg-slate-900"
          style={{ opacity: pull * 0.35, transition }}
        />
      )}

      {/* Peek panel — iframe of /service-hub follows the drag */}
      {showPreview && (
        <div
          className="absolute inset-y-0 right-0 overflow-hidden bg-white shadow-[-24px_0_60px_-12px_rgba(15,23,42,0.35)]"
          style={{
            width: `${Math.max(88, width - TAB_W - 6)}px`,
            transform: `translateX(${panelTranslatePct}%)`,
            transition,
          }}
        >
          <iframe
            src="/service-hub"
            title="Service Hub"
            className="h-full w-full border-0"
            /* srcDoc fallback removed — internal /service-hub iframes fine */
          />
        </div>
      )}

      {/* The pull tab itself — sticks to the right edge, vertically centered on the nav pill */}
      <button
        type="button"
        aria-label="Open Service Hub"
        onPointerDown={(e) => onDown(e.clientX, e.currentTarget, e.pointerId)}
        onPointerMove={(e) => onMove(e.clientX)}
        onPointerUp={onUp}
        onPointerCancel={onUp}
        style={{
          transform: `translateX(-${tabTranslatePx}px)`,
          transition,
        }}
        className="pointer-events-auto absolute bottom-[26px] right-0 flex h-[68px] w-[34px] touch-none items-center justify-center rounded-l-2xl bg-gradient-to-br from-brand via-brand-700 to-brand-dark text-gold-200 shadow-[0_8px_28px_-4px_rgba(26,53,86,0.5)] ring-1 ring-gold-300/50 active:scale-[0.96]"
      >
        {/* Vertical "grip" line + icon */}
        <span className="pointer-events-none absolute inset-y-3 left-1 w-0.5 rounded-full bg-gold-300/50" />
        {pull > 0.05 ? <ChevronLeft size={17} /> : <Sparkles size={17} />}
      </button>
    </div>
  );
}
