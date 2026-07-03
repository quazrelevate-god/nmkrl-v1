"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, MapPin } from "lucide-react";

const TABS = [
  { href: "/",    label: "Report",       Icon: Home  },
  { href: "/map", label: "Map & History", Icon: MapPin },
];

export default function BottomNav() {
  const pathname = usePathname();
  return (
    <nav className="absolute bottom-0 left-0 right-0 z-[500] border-t border-slate-200 bg-white/95 backdrop-blur">
      <div className="flex items-stretch justify-around px-2 py-2">
        {TABS.map(({ href, label, Icon }) => {
          const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={`flex flex-1 flex-col items-center gap-1 rounded-xl py-1.5 text-[11px] font-medium transition ${
                active ? "text-brand" : "text-slate-400 hover:text-slate-600"
              }`}
            >
              <Icon size={22} strokeWidth={active ? 2.2 : 1.7} />
              {label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
