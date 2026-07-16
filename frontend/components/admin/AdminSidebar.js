"use client";

/**
 * AdminSidebar
 * ------------
 * Light-grey frosted rail for the Petition Management staff portal. Three sections —
 * Performance, Tickets (live open-count badge), Petition Review (pending-
 * verification badge) — plus the signed-in staff footer.
 */

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Ticket, ClipboardCheck, Megaphone, Users, Landmark, LogOut, FolderTree, Network } from "lucide-react";
import { useAdminData } from "./AdminDataProvider";
import { listCoordinators } from "@/lib/coordinators";
import { listPending, MODERATION_EVENT } from "@/lib/postModeration";

const NAV = [
  { href: "/admin/performance", label: "Performance", icon: LayoutDashboard, badgeKey: null },
  { href: "/admin", label: "Tickets", icon: Ticket, badgeKey: "tickets" },
  { href: "/admin/petition-review", label: "Petition Review", icon: ClipboardCheck, badgeKey: "pending" },
  { href: "/admin/post-review", label: "Post Review", icon: Megaphone, badgeKey: "postReview" },
  { href: "/admin/departments", label: "Departments", icon: FolderTree, badgeKey: null },
  { href: "/admin/routing", label: "Dept Routing", icon: Network, badgeKey: null },
  { href: "/admin/coordinators", label: "Coordinators", icon: Users, badgeKey: "coordinators" },
];

export default function AdminSidebar() {
  const pathname = usePathname();
  const { tickets, pending } = useAdminData();

  // Live coordinator count, refreshes when the admin creates/disables users
  // (both this sidebar and the /admin/coordinators page listen for the event).
  const [coordinatorCount, setCoordinatorCount] = useState(0);
  useEffect(() => {
    const sync = () => setCoordinatorCount(listCoordinators().length);
    sync();
    const listener = () => sync();
    window.addEventListener("fms:coordinator-directory-changed", listener);
    return () => window.removeEventListener("fms:coordinator-directory-changed", listener);
  }, []);

  // Live pending-post count, refreshes on approve/reject or new coordinator posts.
  const [pendingPosts, setPendingPosts] = useState(0);
  useEffect(() => {
    const sync = () => setPendingPosts(listPending().length);
    sync();
    window.addEventListener(MODERATION_EVENT, sync);
    // Post creation happens on other tabs / coordinator side — poll every 5s
    // to catch new pending submissions when this sidebar isn't the focus.
    const iv = setInterval(sync, 5000);
    return () => {
      window.removeEventListener(MODERATION_EVENT, sync);
      clearInterval(iv);
    };
  }, []);

  const badges = {
    tickets: tickets.length,
    pending: pending.length,
    postReview: pendingPosts,
    coordinators: coordinatorCount,
  };

  return (
    <aside className="glass-sidebar flex h-screen w-60 shrink-0 flex-col text-slate-600">
      {/* Brand */}
      <div className="flex items-center gap-3 px-5 pb-5 pt-6">
        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-brand to-brand-dark shadow-lg shadow-brand/30 ring-1 ring-white/40">
          <Landmark size={22} className="text-amber-300" />
        </div>
        <div>
          <p className="text-[15px] font-extrabold leading-tight text-slate-800">Petition Management</p>
          <p className="text-[11px] font-medium text-slate-500">Staff Portal</p>
        </div>
      </div>

      <p className="px-5 pb-2 pt-3 text-[10px] font-bold uppercase tracking-widest text-slate-400">Menu</p>

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
                  : "text-slate-600 hover:bg-slate-900/5"
              }`}
            >
              <Icon size={18} className={active ? "text-amber-300" : "text-slate-500 group-hover:text-slate-700"} />
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
      <div className="mt-auto border-t border-slate-900/10 px-4 py-4">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-800 text-xs font-bold text-white">AD</div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-slate-800">admin</p>
            <p className="truncate text-[11px] text-slate-500">PA Office</p>
          </div>
          <Link href="/" title="Exit to citizen app" className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-900/5 hover:text-slate-800">
            <LogOut size={16} />
          </Link>
        </div>
      </div>
    </aside>
  );
}
