"use client";

/**
 * CategoryCard
 * ------------
 * Full-bleed gradient category tile matching the reference design:
 *   • Vibrant diagonal gradient fill (per-category, from portals.json)
 *   • White title (up to 2 lines) + muted-white description
 *   • Circular translucent "arrow" affordance at the bottom-left
 *   • Large illustration on the right (icon by default; drops in a real
 *     illustration image when `category.image` is set)
 */

import Link from "next/link";
import {
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home as HomeIcon, Wallet, Bus, ArrowRight,
} from "lucide-react";

const CATEGORY_ICON = {
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home: HomeIcon, Wallet, Bus,
};

export default function CategoryCard({ category }) {
  const Icon = CATEGORY_ICON[category.icon] || IdCard;
  const [from, to] = category.gradient || ["#2E74EF", "#5AA0F8"];

  return (
    <Link
      href={`/service-hub/category/${category.slug}`}
      className="relative flex min-h-[150px] flex-col justify-between overflow-hidden rounded-3xl p-3.5 shadow-md transition active:scale-[.98]"
      style={{ backgroundImage: `linear-gradient(135deg, ${from} 0%, ${to} 100%)` }}
    >
      {/* Illustration on the right */}
      <div className="pointer-events-none absolute -right-2 top-1/2 -translate-y-1/2" aria-hidden>
        {category.image ? (
          <img src={category.image} alt="" className="h-24 w-24 object-contain drop-shadow-lg" />
        ) : (
          <div className="relative flex h-24 w-24 items-center justify-center">
            <span className="absolute h-16 w-16 rounded-2xl bg-white/15 blur-[2px]" />
            <span className="absolute h-11 w-11 -translate-x-4 translate-y-5 rounded-xl bg-white/10" />
            <Icon
              size={52}
              strokeWidth={1.6}
              className="relative text-white"
              style={{ filter: "drop-shadow(0 4px 8px rgba(0,0,0,0.22))" }}
            />
          </div>
        )}
      </div>

      {/* Title + description */}
      <div className="relative z-10 max-w-[64%]">
        <h3 className="text-[16px] font-extrabold leading-[1.15] tracking-tight text-white">
          {category.name}
        </h3>
        {category.tagline && (
          <p className="mt-1 text-[10.5px] font-medium leading-snug text-white/80">
            {category.tagline}
          </p>
        )}
      </div>

      {/* Arrow affordance */}
      <div className="relative z-10">
        <span className="flex h-8 w-8 items-center justify-center rounded-full bg-white/25 ring-1 ring-white/30 backdrop-blur-sm">
          <ArrowRight size={16} className="text-white" strokeWidth={2.4} />
        </span>
      </div>
    </Link>
  );
}
