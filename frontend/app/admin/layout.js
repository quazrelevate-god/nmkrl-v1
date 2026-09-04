"use client";

/**
 * Admin layout — shared shell for the Petition Management staff portal.
 * Renders the dark sidebar rail + the active page inside a light workspace.
 * Data is loaded once by AdminDataProvider and shared across all admin pages.
 *
 * It is also the gate: no admin page mounts, and therefore no admin request
 * fires, until a signed token is present and the server has accepted it. The
 * real lock is server-side — this only decides what to show while we ask.
 */

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { AdminDataProvider } from "@/components/admin/AdminDataProvider";
import AdminSidebar from "@/components/admin/AdminSidebar";
import LiquidBackground from "@/components/admin/LiquidBackground";
import { verifyAdminToken } from "@/lib/adminAuth";

export default function AdminLayout({ children }) {
  const router = useRouter();
  const pathname = usePathname();
  const isLoginPage = pathname === "/admin/login";
  // null = still checking, so we never flash the console at a signed-out
  // operator or the login form at a signed-in one.
  const [allowed, setAllowed] = useState(null);

  useEffect(() => {
    if (isLoginPage) return;
    let live = true;
    verifyAdminToken().then((ok) => {
      if (!live) return;
      if (ok) setAllowed(true);
      else router.replace("/admin/login");
    });
    return () => { live = false; };
  }, [isLoginPage, pathname, router]);

  if (isLoginPage) return children;

  if (allowed !== true) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-slate-950 text-sm text-slate-400">
        Checking your sign-in…
      </div>
    );
  }

  return (
    <AdminDataProvider>
      <div className="admin-bg admin-noise relative flex h-screen w-full overflow-hidden text-slate-900">
        <LiquidBackground />
        <div className="relative z-10 flex h-full w-full min-w-0">
          <AdminSidebar />
          <main className="flex min-w-0 flex-1 flex-col overflow-hidden">{children}</main>
        </div>
      </div>
    </AdminDataProvider>
  );
}
