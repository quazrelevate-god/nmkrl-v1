"use client";

/**
 * CategoryRow — compact list-view row for a category (grid/list toggle).
 * Small gradient icon tile + name + description, links into the category page.
 */

import Link from "next/link";
import {
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home as HomeIcon, Wallet, Bus, ChevronRight,
} from "lucide-react";

const CATEGORY_ICON = {
  IdCard, Zap, Shield, GraduationCap, Heart, Landmark, Sprout,
  Briefcase, Home: HomeIcon, Wallet, Bus,
};

export default function CategoryRow({ category }) {
  const Icon = CATEGORY_ICON[category.icon] || IdCard;
  const [from, to] = category.gradient || ["#2E74EF", "#5AA0F8"];

  return (
    <Link
      href={`/service-hub/category/${category.slug}`}
      className="glass-strong group flex items-center gap-3 rounded-2xl p-2.5 transition active:scale-[.99]"
    >
      <span
        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-white shadow-sm"
        style={{ backgroundImage: `linear-gradient(135deg, ${from}, ${to})` }}
      >
        <Icon size={20} strokeWidth={1.9} />
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[13px] font-extrabold tracking-tight text-slate-900">
          {category.name}
        </p>
        <p className="truncate text-[11px] font-medium text-slate-500">{category.tagline}</p>
      </div>
      <ChevronRight size={16} className="shrink-0 text-slate-400 transition group-hover:text-brand" />
    </Link>
  );
}
