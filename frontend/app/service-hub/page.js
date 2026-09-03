"use client";

/**
 * /service-hub — home screen.
 *
 * New layout: browse by CATEGORY. Each category is a big illustrated card in
 * a 2-column grid. Tapping a card opens /service-hub/category/[slug] which
 * lists the portals inside. The top of this page keeps:
 *   • Ask-assistant search bar (opens inline chat)
 *   • Latest schemes auto-scrolling carousel
 */

import { useRef, useState } from "react";
import {
  Search, Sparkles, ChevronRight, LayoutGrid, LayoutList,
} from "lucide-react";
import MobileShell from "@/components/MobileShell";
import ChatBot from "@/components/service-hub/ChatBot";
import CategoryCard from "@/components/service-hub/CategoryCard";
import CategoryRow from "@/components/service-hub/CategoryRow";
import SchemeCarousel from "@/components/service-hub/SchemeCarousel";
import portalsData from "@/lib/portals.json";

export default function ServiceHubPage() {
  const [chatDraft, setChatDraft] = useState("");
  const [chatOpen, setChatOpen] = useState(false);
  const [initialQuery, setInitialQuery] = useState("");
  const [view, setView] = useState("grid"); // "grid" | "list"
  const chatRef = useRef(null);

  const { categories, schemes } = portalsData;

  function openAssistantWith(query) {
    setInitialQuery(query || "");
    setChatOpen(true);
    if (query) setChatDraft("");
    setTimeout(() => chatRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
  }

  function submitSearch(e) {
    e?.preventDefault();
    if (!chatDraft.trim()) return;
    openAssistantWith(chatDraft.trim());
  }

  return (
    <MobileShell>
      {/* Hero */}
      <section className="pt-2">
        <span className="inline-flex items-center gap-1 rounded-full bg-brand/10 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider text-brand">
          <Sparkles size={11} /> Service Hub
        </span>
        <h1 className="mt-2 text-2xl font-extrabold tracking-tight text-slate-900">
          Every Tamil Nadu service, in one place.
        </h1>
        <p className="mt-1 text-[12.5px] leading-relaxed text-slate-500">
          Discover government portals, browse schemes, and ask the assistant — in Tamil or English.
        </p>
      </section>

      {/* Search + assistant */}
      <form onSubmit={submitSearch} className="mt-4">
        <div className="glass-strong flex items-center gap-2 rounded-2xl py-1.5 pl-3 pr-1.5 shadow-sm">
          <Search size={15} className="shrink-0 text-brand" />
          <input
            value={chatDraft}
            onChange={(e) => setChatDraft(e.target.value)}
            type="text"
            placeholder="Ask about a scheme or portal…"
            className="min-w-0 flex-1 bg-transparent py-1 text-[13px] text-slate-800 outline-none placeholder:text-slate-400"
          />
          <button
            type="submit"
            aria-label="Ask assistant"
            className="flex h-8 shrink-0 items-center gap-1 rounded-full bg-brand px-3 text-[11px] font-bold text-white shadow-sm shadow-brand/30 transition active:scale-95"
          >
            <Sparkles size={12} /> Ask
          </button>
        </div>
        <button
          type="button"
          onClick={() => openAssistantWith("")}
          className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-full border border-brand/25 bg-white/70 py-2 text-[11.5px] font-semibold text-brand transition active:scale-[.98]"
        >
          Open chat with assistant
          <ChevronRight size={13} />
        </button>
      </form>

      {chatOpen && (
        <section ref={chatRef} className="mt-4">
          <ChatBot
            variant="inline"
            initialMessage={initialQuery}
            autoSendInitial={!!initialQuery}
            greeting="Hi. Ask me anything about Tamil Nadu government portals, schemes, or services. I can guide you step by step."
          />
        </section>
      )}

      {/* Highlights */}
      <section className="mt-5">
        <SectionHeader eyebrow="Highlights" title="Latest schemes" />
        <SchemeCarousel schemes={schemes} />
      </section>

      {/* Categories */}
      <section className="mt-6">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-[17px] font-extrabold tracking-tight text-slate-900">
            Browse by category
          </h2>
          <div className="flex items-center gap-0.5 rounded-full bg-slate-100 p-0.5">
            <button
              onClick={() => setView("grid")}
              aria-label="Grid view"
              className={`flex h-7 w-7 items-center justify-center rounded-full transition ${
                view === "grid" ? "bg-white text-brand shadow-sm" : "text-slate-400"
              }`}
            >
              <LayoutGrid size={14} />
            </button>
            <button
              onClick={() => setView("list")}
              aria-label="List view"
              className={`flex h-7 w-7 items-center justify-center rounded-full transition ${
                view === "list" ? "bg-white text-brand shadow-sm" : "text-slate-400"
              }`}
            >
              <LayoutList size={14} />
            </button>
          </div>
        </div>

        {view === "grid" ? (
          <div className="grid grid-cols-2 gap-3">
            {categories.map((cat) => (
              <CategoryCard key={cat.slug} category={cat} />
            ))}
          </div>
        ) : (
          <div className="space-y-2">
            {categories.map((cat) => (
              <CategoryRow key={cat.slug} category={cat} />
            ))}
          </div>
        )}
      </section>
    </MobileShell>
  );
}

function SectionHeader({ eyebrow, title, subtitle }) {
  return (
    <div className="mb-2">
      <p className="text-[9.5px] font-bold uppercase tracking-wider text-brand">{eyebrow}</p>
      <h2 className="text-[16px] font-extrabold tracking-tight text-slate-900">{title}</h2>
      {subtitle && <p className="mt-0.5 text-[11.5px] text-slate-500">{subtitle}</p>}
    </div>
  );
}
