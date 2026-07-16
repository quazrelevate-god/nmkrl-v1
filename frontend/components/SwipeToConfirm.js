"use client";

/**
 * SwipeToConfirm
 * --------------
 * iOS "slide to answer"-style confirmation control. The user drags the knob
 * from left to right; once it passes ~85% of the track it locks in and fires
 * onConfirm. Used in place of a tap button for grievance submit + support so
 * the action feels deliberate. Pointer-events based (touch + mouse).
 *
 * Pass a changing `resetToken` to snap the control back to start (e.g. after a
 * failed submit).
 */

import { useEffect, useRef, useState } from "react";
import { ChevronsRight, Check } from "lucide-react";

const KNOB = 48;
const PAD = 4;

export default function SwipeToConfirm({
  label = "Swipe to confirm",
  busyLabel = "Submitting…",
  onConfirm,
  disabled = false,
  busy = false,
  tone = "brand", // brand | emerald
  resetToken = 0,
}) {
  const trackRef = useRef(null);
  const [x, setX] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const start = useRef(null);

  useEffect(() => { setX(0); setConfirmed(false); setDragging(false); start.current = null; }, [resetToken]);

  const maxX = () => Math.max(0, (trackRef.current?.offsetWidth || 320) - KNOB - PAD * 2);

  function onDown(e) {
    if (disabled || busy || confirmed) return;
    start.current = { px: e.clientX, x0: x };
    setDragging(true);
    e.currentTarget.setPointerCapture?.(e.pointerId);
  }
  function onMove(e) {
    if (start.current == null) return;
    const dx = e.clientX - start.current.px;
    setX(Math.max(0, Math.min(maxX(), start.current.x0 + dx)));
  }
  function onUp() {
    if (start.current == null) return;
    start.current = null;
    setDragging(false);
    if (x >= maxX() * 0.85) {
      setX(maxX());
      setConfirmed(true);
      onConfirm?.();
    } else {
      setX(0);
    }
  }

  const m = maxX() || 1;
  const pct = x / m;
  const fillTone = tone === "emerald" ? "from-emerald-500 to-emerald-600" : "from-brand to-brand-dark";
  const trans = dragging ? "none" : "transform .32s cubic-bezier(.22,1,.36,1), width .32s cubic-bezier(.22,1,.36,1)";

  return (
    <div
      ref={trackRef}
      className={`relative h-14 w-full select-none overflow-hidden rounded-2xl bg-slate-100 ring-1 ring-slate-200 ${disabled ? "opacity-50" : ""}`}
    >
      {/* progress fill */}
      <div
        className={`absolute inset-y-0 left-0 bg-gradient-to-r ${fillTone}`}
        style={{ width: x + KNOB + PAD, transition: trans }}
      />

      {/* track label */}
      <div
        className="pointer-events-none absolute inset-0 flex items-center justify-center pl-10 text-sm font-bold"
        style={{ color: pct > 0.45 || confirmed ? "#ffffff" : "#64748b", transition: "color .2s ease" }}
      >
        {busy ? busyLabel : confirmed ? "Confirmed" : label}
      </div>

      {/* animated hint chevrons (idle only) */}
      {!confirmed && !busy && pct < 0.2 && (
        <div className="pointer-events-none absolute inset-y-0 right-5 flex items-center gap-0.5 text-slate-300">
          <span className="swipe-hint" style={{ animationDelay: "0s" }}>›</span>
          <span className="swipe-hint" style={{ animationDelay: ".15s" }}>›</span>
          <span className="swipe-hint" style={{ animationDelay: ".3s" }}>›</span>
        </div>
      )}

      {/* knob */}
      <button
        type="button"
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
        onPointerCancel={onUp}
        aria-label={label}
        style={{ transform: `translateX(${x}px)`, transition: trans }}
        className="absolute left-1 top-1 flex h-12 w-12 touch-none items-center justify-center rounded-xl bg-white text-brand shadow-md active:scale-95"
      >
        {confirmed || busy ? <Check size={22} /> : <ChevronsRight size={22} />}
      </button>

      <style jsx>{`
        .swipe-hint {
          font-size: 20px;
          font-weight: 800;
          line-height: 1;
          animation: swipe-hint 1.1s ease-in-out infinite;
        }
        @keyframes swipe-hint {
          0%, 100% { opacity: 0.25; transform: translateX(0); }
          50% { opacity: 0.9; transform: translateX(3px); }
        }
      `}</style>
    </div>
  );
}
