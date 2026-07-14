"use client";

/**
 * /service-hub/category/[slug] — portals inside a category.
 *
 * Reached by tapping a CategoryCard on /service-hub. Shows:
 *   • Illustrated header (same tone palette as the card)
 *   • Compact list of PortalRows, each linking to /service-hub/portal/[slug]
 *   • Empty-state fallback for categories with no portals yet
 */

import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { useMemo } from "react";
import {
  ArrowLeft,
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home as HomeIcon, Wallet, Bus,
} from "lucide-react";
import MobileShell from "@/components/MobileShell";
import PortalRow from "@/components/service-hub/PortalRow";
import portalsData from "@/lib/portals.json";

const CATEGORY_ICON = {
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home: HomeIcon, Wallet, Bus,
};

export default function CategoryPage() {
  const { slug } = useParams();
  const router = useRouter();

  const category = portalsData.categories.find((c) => c.slug === slug);
  const portals = useMemo(
    () => (category ? portalsData.portals.filter((p) => p.category === category.slug) : []),
    [category]
  );

  if (!category) {
    return (
      <MobileShell>
        <div className="pt-16 text-center">
          <h1 className="text-lg font-extrabold tracking-tight text-slate-900">Category not found</h1>
          <p className="mt-1 text-[12px] text-slate-500">
            The category you're looking for isn't in the directory yet.
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

  const Icon = CATEGORY_ICON[category.icon] || IdCard;
  const [from, to] = category.gradient || ["#2E74EF", "#5AA0F8"];

  return (
    <MobileShell>
      {/* Back link */}
      <button
        onClick={() => router.push("/service-hub")}
        className="flex items-center gap-1.5 py-2 text-[12px] font-bold text-brand active:scale-95"
      >
        <ArrowLeft size={14} /> Service Hub
      </button>

      {/* Gradient header (matches the category card style) */}
      <section
        className="relative overflow-hidden rounded-3xl p-5 shadow-md"
        style={{ backgroundImage: `linear-gradient(135deg, ${from} 0%, ${to} 100%)` }}
      >
        {/* Illustration */}
        <div className="pointer-events-none absolute -right-3 top-1/2 -translate-y-1/2" aria-hidden>
          {category.image ? (
            <img src={category.image} alt="" className="h-32 w-32 object-contain drop-shadow-lg" />
          ) : (
            <div className="relative flex h-32 w-32 items-center justify-center">
              <span className="absolute h-20 w-20 rounded-3xl bg-white/15 blur-[2px]" />
              <span className="absolute h-14 w-14 -translate-x-6 translate-y-7 rounded-2xl bg-white/10" />
              <Icon
                size={68}
                strokeWidth={1.5}
                className="relative text-white"
                style={{ filter: "drop-shadow(0 5px 10px rgba(0,0,0,0.22))" }}
              />
            </div>
          )}
        </div>

        <div className="relative z-10 max-w-[62%]">
          <h1 className="text-2xl font-extrabold leading-tight tracking-tight text-white">
            {category.name}
          </h1>
          {category.tagline && (
            <p className="mt-1 text-[12px] font-medium leading-snug text-white/85">{category.tagline}</p>
          )}
          <div className="mt-3 inline-flex items-center gap-1 rounded-full bg-white/25 px-2.5 py-0.5 text-[10.5px] font-bold text-white ring-1 ring-white/25 backdrop-blur-sm">
            {portals.length} {portals.length === 1 ? "portal" : "portals"}
          </div>
        </div>
      </section>

      {/* Portals list */}
      <section className="mt-4 space-y-2">
        {portals.length ? (
          portals.map((p) => <PortalRow key={p.slug} portal={p} />)
        ) : (
          <div className="rounded-2xl border border-dashed border-slate-300 bg-white/60 p-6 text-center">
            <p className="text-[12.5px] text-slate-500">
              No portals in this category yet. Ask the assistant for the closest match.
            </p>
          </div>
        )}
      </section>
    </MobileShell>
  );
}
