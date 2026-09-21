"use client";

/**
 * AdminSidebar
 * ------------
 * Light-grey frosted rail for the Namkural GMS Portal staff console. Three sections —
 * Performance, Tickets (live open-count badge), Petition Review (pending-
 * verification badge) — plus the signed-in staff footer.
 *
 * Under the brand sits the corporation toggle (Tambaram | Chennai). It switches
 * the LIVE corporation for everyone — the mobile apps' map, wards and filing
 * area follow it — and moves this console to that corporation's office.
 */

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LayoutDashboard, Ticket, ClipboardCheck, Megaphone, Users, Landmark, LogOut, FolderTree, Network, Loader2 } from "lucide-react";
import { useAdminData } from "./AdminDataProvider";
import { listCoordinatorsRemote } from "@/lib/coordinators";
import { listPending, MODERATION_EVENT } from "@/lib/postModeration";
import { adminLogout, getAdminUser, switchCorporation } from "@/lib/adminAuth";
import { fetchAdminCorporation } from "@/lib/api";

// Shown until the server's list arrives, in the same order it sends.
const CORPORATIONS = [
  { id: "tambaram", short_name: "Tambaram", name: "Tambaram City Municipal Corporation" },
  { id: "chennai", short_name: "Chennai", name: "Greater Chennai Corporation" },
];

/** Tambaram | Chennai switch for the live corporation. */
function CorporationToggle({ current }) {
  const [choices, setChoices] = useState(CORPORATIONS);
  const [live, setLive] = useState(current || null);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => { if (current) setLive(current); }, [current]);
  useEffect(() => {
    let alive = true;
    fetchAdminCorporation()
      .then((d) => {
        if (!alive) return;
        if (Array.isArray(d.available) && d.available.length) setChoices(d.available);
        if (!current) setLive(d.active);
      })
      .catch(() => {});
    return () => { alive = false; };
  }, [current]);

  async function pick(c) {
    if (busy || c.id === live) return;
    const from = choices.find((x) => x.id === live)?.short_name || "the current corporation";
    const ok = window.confirm(
      `Switch the app to ${c.name}?\n\n` +
      `Citizens and coordinators will see ${c.short_name}'s map and wards from their next refresh, ` +
      `and new grievances can be filed only inside ${c.short_name}. ` +
      `${from} coordinators are paused until you switch back. Nothing is deleted.`
    );
    if (!ok) return;
    setBusy(c.id);
    setError("");
    try {
      await switchCorporation(c.id);
      // Every page's data belongs to the other office now; start clean.
      window.location.reload();
    } catch (err) {
      setError(err.message);
      setBusy(null);
    }
  }

  return (
    <div className="px-4 pb-1">
      <p className="px-1 pb-1.5 text-[10px] font-bold uppercase tracking-widest text-slate-400">Corporation</p>
      <div role="group" aria-label="Live corporation" className="grid grid-cols-2 gap-1 rounded-xl bg-slate-900/5 p-1">
        {choices.map((c) => {
          const on = c.id === live;
          return (
            <button
              key={c.id}
              type="button"
              aria-pressed={on}
              title={on ? `${c.name} is live` : `Switch the app to ${c.name}`}
              disabled={!!busy}
              onClick={() => pick(c)}
              className={`flex items-center justify-center gap-1 rounded-lg px-2 py-1.5 text-xs font-bold transition focus:outline-none focus-visible:ring-2 focus-visible:ring-brand/60 ${
                on ? "bg-white text-brand-dark shadow-sm" : "text-slate-500 hover:text-slate-800"
              } ${busy ? "cursor-wait" : ""}`}
            >
              {busy === c.id && <Loader2 size={12} className="animate-spin" />}
              {c.short_name}
            </button>
          );
        })}
      </div>
      {error && <p className="px-1 pt-1.5 text-[11px] font-medium text-rose-600">{error}</p>}
    </div>
  );
}

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
  const router = useRouter();
  const { tickets, pending, tenant } = useAdminData();

  // Live coordinator count, refreshes when the admin creates/disables users
  // (both this sidebar and the /admin/coordinators page listen for the event).
  //
  // Counts the BACKEND directory, like the coordinators page does. It used to
  // count the bundled demo list instead, so a freshly-wiped office showed
  // "4 coordinators" in the rail next to a page reading "No coordinators".
  // A failed fetch shows nothing rather than falling back to that demo list —
  // a badge nobody can explain is worse than no badge.
  const [coordinatorCount, setCoordinatorCount] = useState(0);
  useEffect(() => {
    let alive = true;
    const sync = () =>
      listCoordinatorsRemote()
        .then((rows) => { if (alive) setCoordinatorCount(rows.length); })
        .catch(() => { if (alive) setCoordinatorCount(0); });
    sync();
    const listener = () => sync();
    window.addEventListener("fms:coordinator-directory-changed", listener);
    return () => {
      alive = false;
      window.removeEventListener("fms:coordinator-directory-changed", listener);
    };
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
          <p className="text-[15px] font-extrabold leading-tight text-slate-800">Namkural GMS Portal</p>
          <p className="truncate text-[11px] font-medium text-slate-500" title={tenant?.constituency || ""}>{tenant?.name || "Staff Portal"}</p>
        </div>
      </div>

      <CorporationToggle current={tenant?.corporation} />

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
            <p className="truncate text-sm font-bold text-slate-800">{getAdminUser() || "admin"}</p>
            <p className="truncate text-[11px] text-slate-500">PA Office</p>
          </div>
          <button
            type="button"
            title="Sign out of the staff portal"
            onClick={() => { adminLogout(); router.replace("/admin/login"); }}
            className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-900/5 hover:text-slate-800"
          >
            <LogOut size={16} />
          </button>
        </div>
      </div>
    </aside>
  );
}
