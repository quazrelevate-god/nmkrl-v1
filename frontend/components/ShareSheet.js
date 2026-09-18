"use client";

/**
 * ShareSheet
 * ----------
 * Social-media style share modal. Presents a horizontally-scrolling row of
 * platform icons (WhatsApp, Telegram, X, Facebook, LinkedIn, Email) plus a
 * "Copy link" row and a "More" row that opens the OS-native share sheet via
 * `navigator.share()` when available.
 *
 * Props
 *   open   – boolean, controls visibility
 *   onClose – () => void, fires on backdrop tap, close button, or Escape
 *   title  – string, headline used by each platform's share URL
 *   text   – string, one-line summary / body of the share
 *   url    – absolute URL that recipients open
 *   variant – "sheet" (bottom sheet inside phone frame, default) | "dialog"
 *             (centred, for desktop coordinator pages)
 */

import { useEffect, useMemo, useState } from "react";
import { X, Share as ShareIcon } from "lucide-react";

export default function ShareSheet({
  open,
  onClose,
  title = "",
  text = "",
  url = "",
  variant = "sheet",
}) {
  const [nativeAvailable, setNativeAvailable] = useState(false);

  useEffect(() => {
    if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
      setNativeAvailable(true);
    }
  }, []);

  // Close on Escape.
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => e.key === "Escape" && onClose?.();
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  const shareUrl = url || (typeof window !== "undefined" ? window.location.href : "");
  const composed = useMemo(() => {
    // The line that arrives in the recipient's chat: headline + summary + link.
    const parts = [];
    if (title) parts.push(title);
    if (text) parts.push(text);
    if (shareUrl) parts.push(shareUrl);
    return parts.join("\n\n");
  }, [title, text, shareUrl]);

  const platforms = useMemo(
    () => [
      {
        id: "whatsapp",
        label: "WhatsApp",
        tint: "bg-emerald-500",
        icon: WhatsAppIcon,
        href: `https://wa.me/?text=${encodeURIComponent(composed)}`,
      },
      {
        id: "telegram",
        label: "Telegram",
        tint: "bg-sky-500",
        icon: TelegramIcon,
        href: `https://t.me/share/url?url=${encodeURIComponent(shareUrl)}&text=${encodeURIComponent(
          `${title}\n${text}`.trim()
        )}`,
      },
      {
        id: "x",
        label: "X",
        tint: "bg-slate-900",
        icon: XIcon,
        href: `https://twitter.com/intent/tweet?text=${encodeURIComponent(
          `${title}\n${text}`.trim()
        )}&url=${encodeURIComponent(shareUrl)}`,
      },
      {
        id: "facebook",
        label: "Facebook",
        tint: "bg-blue-600",
        icon: FacebookIcon,
        href: `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(shareUrl)}&quote=${encodeURIComponent(
          `${title} — ${text}`.trim()
        )}`,
      },
      {
        id: "linkedin",
        label: "LinkedIn",
        tint: "bg-[#0A66C2]",
        icon: LinkedInIcon,
        href: `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(shareUrl)}`,
      },
      {
        id: "email",
        label: "Email",
        tint: "bg-amber-500",
        icon: EmailIcon,
        href: `mailto:?subject=${encodeURIComponent(title || "Namkural")}&body=${encodeURIComponent(
          composed
        )}`,
      },
    ],
    [composed, shareUrl, title, text]
  );

  async function nativeShare() {
    try {
      await navigator.share({ title, text, url: shareUrl });
      onClose?.();
    } catch {
      /* user cancelled — no-op */
    }
  }

  if (!open) return null;

  // Sheet variant is anchored inside the MobileShell's max-w-md frame, so it
  // uses absolute positioning within the nearest positioned ancestor. Dialog
  // variant is fixed and centred for desktop surfaces.
  const isDialog = variant === "dialog";
  const wrapperCls = isDialog
    ? "fixed inset-0 z-[900] flex items-center justify-center"
    : "absolute inset-0 z-[720] flex items-end justify-center";
  const cardCls = isDialog
    ? "relative w-[min(420px,calc(100%-2rem))] rounded-3xl bg-white p-5 shadow-2xl animate-modal-float"
    : "relative w-full rounded-t-3xl bg-white p-4 pb-6 shadow-2xl animate-sheet-up";

  return (
    <div className={wrapperCls} role="dialog" aria-modal="true">
      <div
        className="absolute inset-0 bg-slate-900/50 animate-scrim-in"
        onClick={onClose}
        aria-hidden
      />

      <div className={cardCls}>
        {/* Drag handle (sheet only) */}
        {!isDialog && (
          <div className="mx-auto mb-3 h-1.5 w-10 rounded-full bg-slate-200" aria-hidden />
        )}

        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[15px] font-extrabold tracking-tight text-slate-900">
              Share
            </p>
            {title && (
              <p className="mt-0.5 line-clamp-1 text-[12px] text-slate-500">{title}</p>
            )}
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-100 text-slate-500 active:scale-95"
          >
            <X size={16} />
          </button>
        </div>

        {/* Platform icons — horizontal scroll on narrow, wraps on wider */}
        <div className="no-scrollbar mt-4 flex gap-3 overflow-x-auto pb-1">
          {platforms.map((p) => (
            <a
              key={p.id}
              href={p.href}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => setTimeout(() => onClose?.(), 250)}
              className="flex w-16 shrink-0 flex-col items-center gap-1.5 active:scale-95"
            >
              <span className={`flex h-12 w-12 items-center justify-center rounded-full text-white shadow-sm ${p.tint}`}>
                <p.icon />
              </span>
              <span className="text-[11px] font-semibold text-slate-700">{p.label}</span>
            </a>
          ))}
        </div>

        {/* Native share (only when browser supports it) */}
        {nativeAvailable && (
          <button
            onClick={nativeShare}
            className="mt-4 flex w-full items-center justify-center gap-1.5 rounded-full border border-slate-200 bg-white py-2.5 text-[12px] font-bold text-slate-700 active:scale-[.98]"
          >
            <ShareIcon size={13} /> More share options
          </button>
        )}
      </div>
    </div>
  );
}

/* ── Brand-mark SVG icons (inline, 20px, monochrome white) ────────────────── */
function WhatsAppIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M20.5 3.5A11.9 11.9 0 0 0 12 0C5.4 0 0 5.4 0 12c0 2.1.6 4.2 1.7 6L0 24l6.2-1.6a12 12 0 0 0 5.8 1.5h.1c6.6 0 12-5.4 12-12 0-3.2-1.3-6.2-3.6-8.4Zm-8.5 18.4c-1.7 0-3.4-.5-4.9-1.4l-.4-.2-3.7 1 1-3.6-.2-.4A9.9 9.9 0 1 1 22 12c0 5.5-4.5 9.9-10 9.9Zm5.5-7.5c-.3-.2-1.8-.9-2-1s-.5-.2-.7.1-.8 1-1 1.2-.4.2-.6.1c-1-.5-1.9-1.1-2.7-2-.7-.7-1.4-1.6-1.7-2.4-.2-.3 0-.4.1-.6l.4-.5c.1-.2.2-.3.3-.5s0-.4 0-.5c-.1-.2-.7-1.7-1-2.3-.3-.6-.5-.5-.7-.5H8c-.2 0-.5.1-.8.4a3 3 0 0 0-.9 2.2c0 1.3.9 2.6 1.1 2.8.1.2 1.8 2.8 4.4 4 2.6 1 3.1.8 3.7.7.6-.1 1.9-.8 2.2-1.5.3-.7.3-1.4.2-1.5 0-.2-.3-.3-.6-.5Z"/>
    </svg>
  );
}
function TelegramIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M23.9 3.4c-.2-.9-1-1.3-1.9-1L1.4 10.6c-.7.3-1.4.7-1.4 1.6 0 .6.5 1 1.4 1.3l5.1 1.7 2 6.2c.2.7.8.8 1.3.5l3.4-2.6 5.7 4.2c1 .5 1.7.2 1.9-.9L23.9 3.4Zm-4.7 3.5-8.4 7.5c-.4.4-.4.5-.4 1l-.4 2.7c0 .2-.1.4-.5.1L8 15.3l10.8-8.4c.5-.3.9 0 .4.4Z"/>
    </svg>
  );
}
function XIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M18.2 2h3.4l-7.5 8.6L23 22h-6.9l-5.4-7-6.2 7H1l8-9.2L1 2h7l4.9 6.4L18.2 2Zm-1.2 18h1.9L7.1 4H5.1L17 20Z"/>
    </svg>
  );
}
function FacebookIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M24 12a12 12 0 1 0-13.9 11.9v-8.4H7v-3.5h3.1V9.4c0-3 1.8-4.7 4.6-4.7 1.3 0 2.7.3 2.7.3v2.9h-1.5c-1.5 0-2 1-2 1.9v2.2h3.4l-.6 3.5h-2.9V24A12 12 0 0 0 24 12Z"/>
    </svg>
  );
}
function LinkedInIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M20.5 20.5h-3.6v-5.6c0-1.3 0-3-1.9-3s-2.1 1.4-2.1 2.9v5.7H9.3V9h3.4v1.6h.1c.5-.9 1.7-1.9 3.4-1.9 3.6 0 4.3 2.4 4.3 5.5v6.3ZM5.3 7.4a2.1 2.1 0 1 1 0-4.2 2.1 2.1 0 0 1 0 4.2Zm1.8 13.1H3.5V9h3.6v11.5ZM22.2 0H1.8C.8 0 0 .8 0 1.8v20.4c0 1 .8 1.8 1.8 1.8h20.4c1 0 1.8-.8 1.8-1.8V1.8c0-1-.8-1.8-1.8-1.8Z"/>
    </svg>
  );
}
function EmailIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="m22 6-10 7L2 6" />
    </svg>
  );
}
