"use client";

/**
 * PortalRow — compact glass row for a single portal.
 * Reused on the category page. Individual portals link to /service-hub/portal/[slug].
 */

import Link from "next/link";
import { ArrowUpRight, ChevronRight } from "lucide-react";

export default function PortalRow({ portal }) {
  return (
    <Link
      href={`/service-hub/portal/${portal.slug}`}
      className="glass-strong group flex items-start gap-3 rounded-2xl p-3 transition active:scale-[.99]"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-brand/10 to-brand/5 text-brand ring-1 ring-brand/15">
        <ArrowUpRight size={18} />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[13px] font-extrabold tracking-tight text-slate-900">
          {portal.name}
        </p>
        <p className="mt-0.5 truncate text-[11px] font-semibold text-brand">{portal.tagline}</p>
        <p className="mt-1 line-clamp-2 text-[11.5px] leading-relaxed text-slate-500">
          {portal.description}
        </p>
      </div>
      <ChevronRight
        size={16}
        className="mt-1 shrink-0 text-slate-400 transition group-hover:translate-x-0.5 group-hover:text-brand"
      />
    </Link>
  );
}
