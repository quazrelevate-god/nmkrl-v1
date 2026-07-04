"use client";

/**
 * Admin layout — shared shell for the Petition Management staff portal.
 * Renders the dark sidebar rail + the active page inside a light workspace.
 * Data is loaded once by AdminDataProvider and shared across all admin pages.
 */

import { AdminDataProvider } from "@/components/admin/AdminDataProvider";
import AdminSidebar from "@/components/admin/AdminSidebar";
import LiquidBackground from "@/components/admin/LiquidBackground";

export default function AdminLayout({ children }) {
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
