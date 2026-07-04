"use client";

/**
 * Admin layout — shared shell for the Petition Management staff portal.
 * Renders the dark sidebar rail + the active page inside a light workspace.
 * Data is loaded once by AdminDataProvider and shared across all admin pages.
 */

import { AdminDataProvider } from "@/components/admin/AdminDataProvider";
import AdminSidebar from "@/components/admin/AdminSidebar";

export default function AdminLayout({ children }) {
  return (
    <AdminDataProvider>
      <div className="flex h-screen w-full overflow-hidden bg-slate-50 text-slate-900">
        <AdminSidebar />
        <main className="flex min-w-0 flex-1 flex-col overflow-hidden">{children}</main>
      </div>
    </AdminDataProvider>
  );
}
