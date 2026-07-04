"use client";

/**
 * AdminSidebar
 * ------------
 * Dark navy rail for the Petition Management staff portal. Three sections —
 * Performance, Tickets (live open-count badge), Petition Review (pending-
 * verification badge) — plus the signed-in staff footer.
 */

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Ticket, ClipboardCheck, Landmark, LogOut } from "lucide-react";
import { useAdminData } from "./AdminDataProvider";

const NAV = [
  { href: "/admin/performance", label: "Performance", icon: LayoutDashboard, badgeKey: null },
  { href: "/admin", label: "Tickets", icon: Ticket, badgeKey: "tickets" },
  { href: "/admin/petition-review", label: "Petition Review", icon: ClipboardCheck, badgeKey: "pending" },
];

export default function AdminSidebar() {
  const pathname = usePathname();
  const { tickets, pending } = useAdminData();
  const badges = { tickets: tickets.length, pending: pending.length };

  return (
    <aside className="glass-dark-panel flex h-screen w-60 shrink-0 flex-col text-slate-300">
      {/* Brand */}
      <div className="flex items-center gap-3 px-5 pb-5 pt-6">
        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-brand to-brand-dark shadow-lg shadow-black/40 ring-1 ring-white/15">
          <Landmark size={22} className="text-amber-300" />
        </div>
        <div>
          <p className="text-[15px] font-extrabold leading-tight text-white">Petition Management</p>
          <p className="text-[11px] font-medium text-slate-400">Staff Portal</p>
        </div>
      </div>

      <p className="px-5 pb-2 pt-3 text-[10px] font-bold uppercase tracking-widest text-slate-500">Menu</p>

      {/* Nav */}
      <nav className="flex-1 space-y-1 px-3">
        {NAV.map(({ href, label, icon: Icon, badgeKey }) => {
          const active = href === "/admin" ? pathname === "/admin" : pathname.startsWith(href);
          const badge = badgeKey ? badges[badgeKey] : 0;
          return (
            <Link
              key={href}
              href={href}
              style={{ transition: "transform .3s cubic-bezier(.22,1,.36,1), background .3s ease" }}
              className={`group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold hover:-translate-y-px ${
                active
                  ? "accent-ring bg-gradient-to-r from-brand to-brand-dark text-white"
                  : "text-slate-300 hover:bg-white/5"
              }`}
            >
              <Icon size={18} className={active ? "text-amber-300" : "text-slate-400 group-hover:text-slate-200"} />
              <span className="flex-1">{label}</span>
              {badge > 0 && (
                <span className={`flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[11px] font-bold ${
                  active ? "bg-amber-400 text-brand-dark" : "bg-brand text-white"
                }`}>
                  {badge}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {/* Staff footer */}
      <div className="mt-auto border-t border-white/10 px-4 py-4">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-xs font-bold text-white">AD</div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-white">admin</p>
            <p className="truncate text-[11px] text-slate-400">PA Office</p>
          </div>
          <Link href="/" title="Exit to citizen app" className="rounded-lg p-1.5 text-slate-400 hover:bg-white/10 hover:text-white">
            <LogOut size={16} />
          </Link>
        </div>
      </div>
    </aside>
  );
}
