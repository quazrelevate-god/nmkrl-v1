"use client";

/**
 * ChatBot — Gemini assistant for the Service Hub.
 *
 * Reskinned to the Namkural citizen PWA design language:
 *   • slate-teal `brand` for accents (no gold/blue/white gimmicks)
 *   • glassy surfaces + soft slate hairlines, matches MobileShell aesthetic
 *   • system font — no Playfair — so it feels native inside the phone frame
 *
 * Variants:
 *   • "inline"   — full-width chat panel embedded in the hub page
 *   • "floating" — absolute-positioned bubble inside the phone frame that
 *                  expands into a sheet-style chat window
 */

import { useEffect, useRef, useState } from "react";
import { Send, X, Loader2, Sparkles, MessageCircle } from "lucide-react";
import { serviceHubChat } from "@/lib/api";

export default function ChatBot({
  variant = "inline",
  portal = null,
  initialMessage = "",
  autoSendInitial = false,   // fire the initial message as soon as it lands
  autoOpen = false,
  greeting,
  className = "",
}) {
  const [open, setOpen] = useState(variant === "inline" || autoOpen);
  const [messages, setMessages] = useState(() => {
    const hi = greeting || (portal
      ? `Hi. I can help you with ${portal.name}. Ask me about applying, tracking, or eligibility.`
      : "Hi. Ask me about any Tamil Nadu government portal, scheme, or service — in Tamil or English.");
    return [{ role: "assistant", text: hi }];
  });
  const [input, setInput] = useState(autoSendInitial ? "" : initialMessage);
  const [busy, setBusy] = useState(false);
  const scrollRef = useRef(null);
  const sentInitialRef = useRef(false);

  useEffect(() => {
    if (!initialMessage) return;
    if (autoSendInitial) {
      if (sentInitialRef.current) return;
      sentInitialRef.current = true;
      send(initialMessage);
    } else {
      setInput(initialMessage);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMessage, autoSendInitial]);
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [messages, open]);

  async function send(overrideText) {
    const text = (overrideText ?? input).trim();
    if (!text || busy) return;
    setInput("");
    const nextHistory = [...messages, { role: "user", text }];
    setMessages(nextHistory);
    setBusy(true);
    try {
      const res = await serviceHubChat({
        message: text,
        history: nextHistory.slice(-6),
        portal: portal ? {
          name: portal.name,
          tagline: portal.tagline,
          url: portal.url,
          description: portal.description,
        } : null,
      });
      setMessages((m) => [...m, { role: "assistant", text: res.reply || "I couldn't get a response — please try again." }]);
    } catch {
      setMessages((m) => [...m, { role: "assistant", text: "Something went wrong. Please try again in a moment." }]);
    } finally {
      setBusy(false);
    }
  }

  function onKey(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  const bubble = (m, i) => (
    <div key={i} className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-[13px] leading-relaxed shadow-sm ${
          m.role === "user"
            ? "bg-brand text-white"
            : "border border-slate-200 bg-white text-slate-800"
        }`}
      >
        {m.text}
      </div>
    </div>
  );

  const inputRow = (
    <div className="flex items-end gap-2 border-t border-slate-200/70 bg-white/70 p-2.5 backdrop-blur">
      <textarea
        value={input}
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={onKey}
        rows={1}
        placeholder={portal ? `Ask about ${portal.name}…` : "Ask about a scheme, certificate, or portal…"}
        className="flex-1 resize-none rounded-xl border border-slate-200 bg-white px-3 py-2 text-[13px] text-slate-800 outline-none placeholder:text-slate-400 focus:border-brand"
      />
      <button
        onClick={() => send()}
        disabled={busy || !input.trim()}
        aria-label="Send"
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-brand text-white shadow-md shadow-brand/30 transition active:scale-95 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {busy ? <Loader2 size={16} className="animate-spin" /> : <Send size={15} />}
      </button>
    </div>
  );

  const suggestionRow = portal?.commonQuestions?.length ? (
    <div className="flex flex-wrap gap-1.5 border-b border-slate-200/70 bg-white/60 px-3 py-2 backdrop-blur">
      {portal.commonQuestions.slice(0, 3).map((q) => (
        <button
          key={q}
          onClick={() => send(q)}
          className="rounded-full border border-brand/25 bg-brand/5 px-2.5 py-1 text-[11px] font-semibold text-brand transition active:scale-95"
        >
          {q}
        </button>
      ))}
    </div>
  ) : null;

  if (variant === "floating") {
    // Positioned absolutely inside the parent MobileShell — sits above the
    // scroll body but below the bottom pill nav (z-700).
    return (
      <>
        {!open && (
          <button
            onClick={() => setOpen(true)}
            aria-label="Ask assistant"
            className="glass-strong absolute bottom-24 right-4 z-[695] flex items-center gap-2 rounded-full px-3.5 py-2.5 shadow-lg shadow-brand/25 transition active:scale-95"
          >
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-gradient-to-br from-brand to-brand-dark text-white">
              <Sparkles size={14} />
            </span>
            <span className="text-[12px] font-semibold text-slate-800">Ask assistant</span>
          </button>
        )}
        {open && (
          <div className="absolute inset-x-3 bottom-24 z-[695] flex max-h-[68%] flex-col overflow-hidden rounded-3xl border border-white/60 bg-white/95 shadow-[0_20px_60px_-10px_rgba(15,23,42,0.35)] backdrop-blur animate-sheet-up">
            <div className="flex items-center gap-2 border-b border-slate-200/70 bg-gradient-to-b from-white to-slate-50 px-3.5 py-2.5">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-brand to-brand-dark text-white">
                <Sparkles size={15} />
              </span>
              <div className="flex-1">
                <p className="text-[13px] font-extrabold tracking-tight text-slate-800">Service Hub assistant</p>
                {portal ? (
                  <p className="text-[10px] font-semibold text-brand">Scoped to {portal.name}</p>
                ) : (
                  <p className="text-[10px] font-semibold text-slate-500">Tamil Nadu government services</p>
                )}
              </div>
              <button
                onClick={() => setOpen(false)}
                aria-label="Close"
                className="rounded-full p-1.5 text-slate-500 hover:bg-slate-100"
              >
                <X size={15} />
              </button>
            </div>
            {suggestionRow}
            <div ref={scrollRef} className="flex-1 space-y-2 overflow-y-auto bg-slate-50/60 p-3">
              {messages.map(bubble)}
              {busy && (
                <div className="flex justify-start">
                  <div className="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-[12px] text-slate-500">
                    <Loader2 size={12} className="mr-1 inline-block animate-spin" /> thinking…
                  </div>
                </div>
              )}
            </div>
            {inputRow}
          </div>
        )}
      </>
    );
  }

  // Inline (full-width panel embedded in the hub page)
  return (
    <div className={`flex flex-col overflow-hidden rounded-3xl border border-white/60 bg-white/85 shadow-sm backdrop-blur ${className}`}>
      <div className="flex items-center gap-2.5 border-b border-slate-200/70 bg-gradient-to-b from-white to-slate-50 px-4 py-3">
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-brand to-brand-dark text-white shadow-sm shadow-brand/40">
          <MessageCircle size={16} />
        </span>
        <div className="flex-1">
          <p className="text-[14px] font-extrabold tracking-tight text-slate-900">Ask the assistant</p>
          <p className="text-[10.5px] font-semibold text-brand">
            Gemini · Tamil Nadu government services
          </p>
        </div>
      </div>
      {suggestionRow}
      <div ref={scrollRef} className="max-h-[360px] min-h-[200px] flex-1 space-y-2 overflow-y-auto bg-slate-50/60 p-3">
        {messages.map(bubble)}
        {busy && (
          <div className="flex justify-start">
            <div className="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-[12px] text-slate-500">
              <Loader2 size={12} className="mr-1 inline-block animate-spin" /> thinking…
            </div>
          </div>
        )}
      </div>
      {inputRow}
    </div>
  );
}
