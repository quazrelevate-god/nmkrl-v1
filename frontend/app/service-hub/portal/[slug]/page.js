"use client";

/**
 * /service-hub/portal/[slug] — portal detail inside the citizen phone frame.
 *
 * Government portals cannot be iframed (X-Frame-Options), so we present the
 * portal cleanly with a big "Open portal" CTA and a floating Gemini assistant
 * bubble scoped to this portal. Styled to match the Namkural PWA brand.
 */

import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import {
  ArrowLeft, ExternalLink, HelpCircle, ShieldCheck,
  Bookmark, FileText, Sparkles, ChevronRight,
} from "lucide-react";
import MobileShell from "@/components/MobileShell";
import ChatBot from "@/components/service-hub/ChatBot";
import portalsData from "@/lib/portals.json";

export default function PortalDetailPage() {
  const { slug } = useParams();
  const router = useRouter();
  const portal = portalsData.portals.find((p) => p.slug === slug);
  const category = portal && portalsData.categories.find((c) => c.slug === portal.category);

  if (!portal) {
    return (
      <MobileShell>
        <div className="pt-16 text-center">
          <h1 className="text-lg font-extrabold tracking-tight text-slate-900">Portal not found</h1>
          <p className="mt-1 text-[12px] text-slate-500">
            The portal you're looking for isn't in our directory yet.
          </p>
          <Link
            href="/service-hub"
            className="mt-5 inline-flex items-center gap-1.5 rounded-full bg-brand px-4 py-2 text-[12px] font-bold text-white shadow-md shadow-brand/30"
          >
            <ArrowLeft size={13} /> Back to Service Hub
          </Link>
        </div>
      </MobileShell>
    );
  }

  return (
    <MobileShell>
      {/* Back header */}
      <button
        onClick={() => router.push("/service-hub")}
        className="flex items-center gap-1.5 py-2 text-[12px] font-bold text-brand active:scale-95"
      >
        <ArrowLeft size={14} /> Service Hub
      </button>

      {/* Hero card */}
      <section className="glass-strong mt-1 rounded-3xl p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-1.5">
          {category && (
            <span className="rounded-full bg-brand/10 px-2 py-0.5 text-[9.5px] font-bold uppercase tracking-wider text-brand">
              {category.name}
            </span>
          )}
          <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[9.5px] font-bold text-emerald-700 ring-1 ring-emerald-200">
            <ShieldCheck size={10} /> Official
          </span>
        </div>
        <h1 className="mt-3 text-xl font-extrabold leading-tight tracking-tight text-slate-900">
          {portal.name}
        </h1>
        <p className="mt-0.5 text-[12px] font-semibold text-brand">{portal.tagline}</p>
        <p className="mt-2 text-[12px] leading-relaxed text-slate-600">{portal.description}</p>

        <div className="mt-3 flex flex-col gap-2">
          <a
            href={portal.url}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center justify-center gap-1.5 rounded-full bg-brand py-2.5 text-[12.5px] font-bold text-white shadow-md shadow-brand/30 active:scale-95"
          >
            <ExternalLink size={13} /> Open {portal.name}
          </a>
          <button
            onClick={() => {
              const el = document.getElementById("ask-cta");
              el?.scrollIntoView({ behavior: "smooth", block: "start" });
            }}
            className="flex items-center justify-center gap-1.5 rounded-full border border-brand/30 bg-white/70 py-2 text-[11.5px] font-bold text-brand active:scale-95"
          >
            <Sparkles size={12} /> Ask assistant about this portal
          </button>
        </div>
      </section>

      {/* Common questions */}
      <section className="glass-strong mt-3 rounded-3xl p-4 shadow-sm">
        <div className="mb-2 flex items-center gap-2">
          <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-brand/10 text-brand">
            <HelpCircle size={14} />
          </span>
          <h3 className="text-[13px] font-extrabold tracking-tight text-slate-900">
            Common questions
          </h3>
        </div>
        <ul className="space-y-1.5">
          {portal.commonQuestions.map((q) => (
            <li
              key={q}
              className="flex items-start gap-2 rounded-xl bg-white/60 px-2.5 py-2 text-[12px] leading-relaxed text-slate-700"
            >
              <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-brand" />
              <span>{q}</span>
            </li>
          ))}
        </ul>
      </section>

      {/* URL + CTA row */}
      <section id="ask-cta" className="glass-strong mt-3 rounded-3xl p-4 shadow-sm">
        <div className="mb-2 flex items-center gap-2">
          <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-brand/10 text-brand">
            <FileText size={14} />
          </span>
          <h3 className="text-[13px] font-extrabold tracking-tight text-slate-900">
            What you can do here
          </h3>
        </div>
        <p className="text-[12px] leading-relaxed text-slate-600">{portal.description}</p>
        <div className="mt-3 flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white/70 px-2.5 py-1.5 text-[10.5px] font-semibold">
          <Bookmark size={11} className="shrink-0 text-brand" />
          <span className="truncate text-slate-600" title={portal.url}>{portal.url}</span>
        </div>
      </section>

      {/* Floating chatbot — sits inside the phone frame, above content, below nav */}
      <ChatBot variant="floating" portal={portal} autoOpen={false} />
    </MobileShell>
  );
}
