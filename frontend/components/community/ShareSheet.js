"use client";

/**
 * ShareSheet
 * ----------
 * Bottom-sheet share picker rendered when a citizen (or coordinator) taps the
 * share icon on a community post or poll. Opens real web-share intents for
 * the platforms that expose them (WhatsApp / X / Facebook / Telegram / Email),
 * falls back to a Copy-link + "paste into app" pattern for Instagram (which
 * has no public web intent).
 *
 * The onShared callback fires whenever a share target is actually invoked so
 * the parent can bump its local share counter — no counter change if the
 * user just closes the sheet.
 */

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { X as CloseIcon, Mail, Share2 as ShareIcon, Copy, Check } from "lucide-react";

/* ─── platform glyphs (lucide 1.21 doesn't ship these brand marks) ─── */
function WhatsAppLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="currentColor" aria-hidden>
      <path d="M27.2 4.8A15.9 15.9 0 0 0 4 25.4L2 30l4.7-1.9A15.9 15.9 0 1 0 27.2 4.8Zm-11.2 24a13 13 0 0 1-6.6-1.8l-.5-.3-2.8 1.1 1.1-2.7-.3-.5A13 13 0 1 1 16 28.8Zm7.6-9.7c-.4-.2-2.5-1.2-2.8-1.4s-.7-.2-.9.2-1.1 1.4-1.3 1.7-.5.2-.9 0a10.4 10.4 0 0 1-3-1.9 11.6 11.6 0 0 1-2.1-2.6c-.2-.4 0-.6.2-.7l.6-.7c.1-.2.2-.4.3-.6a.7.7 0 0 0 0-.7c0-.2-.9-2.2-1.2-3s-.6-.6-.9-.6h-.7a1.5 1.5 0 0 0-1.1.5 4.6 4.6 0 0 0-1.4 3.4 8 8 0 0 0 1.7 4.3c.2.3 3 4.6 7.3 6.3a24.6 24.6 0 0 0 2.4.9 5.8 5.8 0 0 0 2.7.2 4.5 4.5 0 0 0 2.9-2 3.7 3.7 0 0 0 .3-2c-.1-.1-.4-.3-.8-.5Z"/>
    </svg>
  );
}
function XLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M18.244 2H21l-6.44 7.36L22 22h-6.828l-4.79-6.24L4.8 22H2l6.94-7.94L2 2h6.93l4.33 5.72L18.244 2Zm-2.394 18h1.874L7.222 4H5.24l10.61 16Z"/>
    </svg>
  );
}
function FacebookLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M13.5 21v-7.5h2.55L16.5 10.5h-3v-2c0-.9.3-1.5 1.65-1.5H16.5V4.2c-.3-.05-1.35-.15-2.55-.15-2.55 0-4.2 1.5-4.2 4.35v2.1H7.5v3h2.25V21h3.75Z"/>
    </svg>
  );
}
function InstagramLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
         strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="3" y="3" width="18" height="18" rx="5"/>
      <circle cx="12" cy="12" r="4"/>
      <circle cx="17.5" cy="6.5" r="1" fill="currentColor" stroke="none"/>
    </svg>
  );
}
function TelegramLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M9.5 15.3 9.3 19c.4 0 .55-.17.74-.37l1.78-1.7 3.7 2.7c.68.38 1.16.18 1.34-.63L21.4 4.5c.23-1.04-.37-1.45-1.03-1.2L3.5 9.66c-1 .4-1 .95-.18 1.2l4.3 1.34 10-6.3c.46-.3.9-.13.56.17l-8.68 8.23Z"/>
    </svg>
  );
}
function RedditLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M22 12.4a2.6 2.6 0 0 0-4.4-1.85 12 12 0 0 0-5.9-1.85l1-4.7 3.3.7a1.7 1.7 0 1 0 .2-1L12.5 3 11.3 8.7A12 12 0 0 0 5.4 10.55 2.6 2.6 0 1 0 2.9 15c0 3.8 4.1 6.9 9.1 6.9s9.1-3.1 9.1-6.9a2.6 2.6 0 0 0 .9-2.6Zm-15 1.6a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0Zm8.5 4.1c-1 1-3.3 1-3.5 1s-2.5 0-3.5-1a.4.4 0 1 1 .55-.55c.7.7 2.15.75 2.95.75s2.25-.05 2.95-.75a.4.4 0 1 1 .55.55Zm-.5-2.6a1.5 1.5 0 1 1 1.5-1.5 1.5 1.5 0 0 1-1.5 1.5Z"/>
    </svg>
  );
}
function LinkedInLogo({ size = 22 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M4.98 3.5A2.5 2.5 0 0 1 7.48 6a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 2.5-2.5ZM3 8.75h4.5V21H3V8.75Zm7.5 0H14v1.7A4.15 4.15 0 0 1 17.7 8.5c3.9 0 4.3 2.65 4.3 6.1V21h-4.5v-5.55c0-1.3-.02-3-1.85-3S13.5 14 13.5 15.4V21h-4.5V8.75h1.5Z"/>
    </svg>
  );
}

/* ─── one platform tile ─── */
function Tile({ label, bg, color = "text-white", children, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="group flex flex-col items-center gap-1.5 focus:outline-none"
    >
      <span
        className={`grid h-12 w-12 place-items-center rounded-2xl shadow-sm ring-1 ring-black/5 transition group-hover:-translate-y-0.5 group-active:scale-95 ${color}`}
        style={{ background: bg }}
      >
        {children}
      </span>
      <span className="text-[10px] font-semibold text-slate-700">{label}</span>
    </button>
  );
}

function openIntent(url) {
  try { window.open(url, "_blank", "noopener,noreferrer"); } catch { /* pop-up blocked */ }
}

export default function ShareSheet({ open, post, onClose, onShared }) {
  const [copied, setCopied] = useState(false);
  const [instaTip, setInstaTip] = useState(false);

  useEffect(() => {
    if (!open) { setCopied(false); setInstaTip(false); }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.removeEventListener("keydown", onKey); document.body.style.overflow = prev; };
  }, [open, onClose]);

  if (!open || typeof document === "undefined") return null;

  const title = post.title || post.question || "Namm Kural community post";
  const excerpt = (post.body || "").slice(0, 160);
  const shareUrl = `https://nammkural.app/post/${post.id}`;
  const shareText = `${title}\n\n${excerpt}${excerpt ? "\n\n" : ""}Shared from Namm Kural`;

  async function copyLink() {
    try { await navigator.clipboard.writeText(shareUrl); }
    catch { /* older browsers — silently ignore */ }
    setCopied(true);
    onShared?.();
    setTimeout(() => setCopied(false), 1600);
  }

  function share(action) {
    action();
    onShared?.();
  }

  async function systemShare() {
    if (typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ title, text: excerpt, url: shareUrl });
        onShared?.();
      } catch { /* user cancelled — no-op */ }
    } else {
      copyLink();
    }
  }

  return createPortal(
    <div className="fixed inset-0 z-[9500] flex items-end justify-center">
      {/* Backdrop */}
      <button
        aria-label="Close share"
        onClick={onClose}
        className="absolute inset-0 bg-slate-900/55 backdrop-blur-sm animate-fade-up"
        style={{ animationDuration: "180ms" }}
      />

      {/* Sheet */}
      <div
        role="dialog"
        aria-label="Share this post"
        className="relative w-full max-w-md rounded-t-3xl bg-white p-5 pb-8 shadow-[0_-25px_60px_-10px_rgba(0,0,0,0.35)]"
        style={{ animation: "sheet-up .28s cubic-bezier(.22,1,.36,1) both" }}
      >
        <span className="mx-auto mb-4 block h-1.5 w-10 rounded-full bg-slate-200" />

        <div className="flex items-start justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-widest text-slate-400">Share</p>
            <p className="text-base font-black text-slate-800">Send this to friends & family</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1.5 text-slate-400 hover:bg-slate-100">
            <CloseIcon size={18} />
          </button>
        </div>

        {/* Post preview */}
        <div className="mt-3 flex items-start gap-3 rounded-2xl bg-slate-50 p-3 ring-1 ring-slate-100">
          {post.avatar && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={post.avatar} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
          )}
          <div className="min-w-0 flex-1">
            <p className="truncate text-[13px] font-bold text-slate-800">{post.author}</p>
            <p className="line-clamp-2 text-[12.5px] leading-snug text-slate-600">{title}</p>
            <p className="mt-1 truncate text-[10.5px] font-medium text-brand">{shareUrl}</p>
          </div>
          {post.media?.[0] && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={post.media[0]} alt="" className="h-12 w-12 shrink-0 rounded-lg object-cover" />
          )}
        </div>

        {/* Platform grid — brand colours match each app */}
        <div className="mt-5 grid grid-cols-4 gap-3">
          <Tile
            label="WhatsApp"
            bg="#25D366"
            onClick={() => share(() => openIntent(`https://wa.me/?text=${encodeURIComponent(shareText + "\n" + shareUrl)}`))}
          >
            <WhatsAppLogo />
          </Tile>
          <Tile
            label="X"
            bg="#000"
            onClick={() => share(() => openIntent(`https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}&url=${encodeURIComponent(shareUrl)}&hashtags=NammKural`))}
          >
            <XLogo />
          </Tile>
          <Tile
            label="Instagram"
            bg="linear-gradient(135deg,#f58529 0%,#dd2a7b 50%,#8134af 100%)"
            onClick={() => { copyLink(); setInstaTip(true); }}
          >
            <InstagramLogo />
          </Tile>
          <Tile
            label="Facebook"
            bg="#1877F2"
            onClick={() => share(() => openIntent(`https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(shareUrl)}&quote=${encodeURIComponent(shareText)}`))}
          >
            <FacebookLogo />
          </Tile>
          <Tile
            label="Telegram"
            bg="#26A5E4"
            onClick={() => share(() => openIntent(`https://t.me/share/url?url=${encodeURIComponent(shareUrl)}&text=${encodeURIComponent(shareText)}`))}
          >
            <TelegramLogo />
          </Tile>
          <Tile
            label="LinkedIn"
            bg="#0A66C2"
            onClick={() => share(() => openIntent(`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(shareUrl)}`))}
          >
            <LinkedInLogo />
          </Tile>
          <Tile
            label="Reddit"
            bg="#FF4500"
            onClick={() => share(() => openIntent(`https://www.reddit.com/submit?url=${encodeURIComponent(shareUrl)}&title=${encodeURIComponent(title)}`))}
          >
            <RedditLogo />
          </Tile>
          <Tile
            label="Email"
            bg="#64748b"
            onClick={() => share(() => openIntent(`mailto:?subject=${encodeURIComponent(title)}&body=${encodeURIComponent(shareText + "\n\n" + shareUrl)}`))}
          >
            <Mail size={22} />
          </Tile>
        </div>

        {instaTip && (
          <div className="mt-4 flex items-start gap-2 rounded-xl bg-rose-50 p-3 text-[12px] text-rose-700 ring-1 ring-rose-100">
            <InstagramLogo size={16} />
            <p><b>Instagram doesn't accept links from the web.</b> The URL is copied — paste it into your Story or DM.</p>
          </div>
        )}

        {/* Utility row */}
        <div className="mt-5 flex items-center gap-2 rounded-2xl bg-slate-50 p-2 ring-1 ring-slate-100">
          <div className="min-w-0 flex-1 truncate rounded-xl bg-white px-3 py-2 text-[12px] font-medium text-slate-500 ring-1 ring-slate-100">
            {shareUrl}
          </div>
          <button
            onClick={copyLink}
            className={`flex items-center gap-1.5 rounded-xl px-3 py-2 text-[12px] font-bold ring-1 transition ${
              copied
                ? "bg-emerald-100 text-emerald-700 ring-emerald-200"
                : "bg-brand text-white ring-brand-700 hover:-translate-y-px"
            }`}
          >
            {copied ? <><Check size={14} /> Copied</> : <><Copy size={14} /> Copy</>}
          </button>
        </div>

        {/* Native OS share (mobile) */}
        <button
          onClick={systemShare}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white py-2.5 text-[13px] font-bold text-slate-700 hover:bg-slate-50"
        >
          <ShareIcon size={15} /> More apps on this device
        </button>

        <style jsx>{`
          @keyframes sheet-up { from { transform: translateY(100%); } to { transform: translateY(0); } }
        `}</style>
      </div>
    </div>,
    document.body,
  );
}
