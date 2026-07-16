"use client";

/**
 * SuccessOverlay
 * --------------
 * Full-screen UPI-style acknowledgement. A green wash sweeps in, a white check
 * badge pops with radiating rings, then the title/message (and optional ticket)
 * fade up. Auto-dismisses after `autoMs`, or on tap. Used for both grievance
 * submission and support confirmation.
 */

import { useEffect } from "react";
import { Check, Ticket } from "lucide-react";

export default function SuccessOverlay({
  open,
  title = "Done",
  message = "",
  ticket = null,
  autoMs = 2800,
  onDone,
}) {
  useEffect(() => {
    if (!open) return;
    const t = setTimeout(() => onDone?.(), autoMs);
    return () => clearTimeout(t);
  }, [open, autoMs, onDone]);

  if (!open) return null;

  return (
    <div
      className="success-overlay fixed inset-0 z-[9600] flex flex-col items-center justify-center overflow-hidden px-8 text-center text-white"
      onClick={() => onDone?.()}
      role="alertdialog"
      aria-label={title}
    >
      {/* radiating rings */}
      <span className="ring-pulse" style={{ animationDelay: "0s" }} />
      <span className="ring-pulse" style={{ animationDelay: ".45s" }} />

      {/* check badge */}
      <div className="check-badge relative flex h-28 w-28 items-center justify-center rounded-full bg-white shadow-2xl">
        <Check className="check-mark text-emerald-600" size={64} strokeWidth={3.2} />
      </div>

      <h2 className="reveal mt-7 text-[26px] font-black tracking-tight" style={{ animationDelay: ".18s" }}>{title}</h2>
      <p className="reveal mt-2 max-w-[85%] text-[14px] leading-relaxed text-white/85" style={{ animationDelay: ".28s" }}>
        {message}
      </p>

      {ticket && (
        <div className="reveal mt-6 rounded-2xl bg-white/15 px-6 py-3 ring-1 ring-white/25 backdrop-blur" style={{ animationDelay: ".38s" }}>
          <p className="flex items-center justify-center gap-1 text-[10px] font-semibold uppercase tracking-[0.2em] text-white/70">
            <Ticket size={11} /> Tracking Ticket
          </p>
          <p className="mt-0.5 select-all text-xl font-black tracking-widest">{ticket}</p>
        </div>
      )}

      <p className="reveal absolute bottom-10 text-[11px] font-medium text-white/60" style={{ animationDelay: ".6s" }}>
        Tap anywhere to continue
      </p>

      <style jsx>{`
        .success-overlay {
          background: radial-gradient(130% 120% at 50% 0%, #12b76a 0%, #059669 45%, #047857 100%);
          animation: sheet-in 0.4s ease both;
        }
        @keyframes sheet-in {
          from { opacity: 0; transform: scale(1.04); }
          to { opacity: 1; transform: scale(1); }
        }
        .check-badge { animation: pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) 0.1s both; }
        @keyframes pop {
          0% { transform: scale(0); opacity: 0; }
          60% { transform: scale(1.12); opacity: 1; }
          100% { transform: scale(1); }
        }
        .check-mark {
          stroke-dasharray: 48;
          stroke-dashoffset: 48;
          animation: draw 0.45s ease 0.42s forwards;
        }
        @keyframes draw { to { stroke-dashoffset: 0; } }
        .ring-pulse {
          position: absolute;
          height: 7rem;
          width: 7rem;
          border-radius: 9999px;
          background: rgba(255, 255, 255, 0.22);
          animation: ring 1.8s ease-out infinite;
        }
        @keyframes ring {
          0% { transform: scale(1); opacity: 0.5; }
          100% { transform: scale(3.4); opacity: 0; }
        }
        .reveal { animation: reveal 0.5s ease both; opacity: 0; }
        @keyframes reveal {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  );
}
