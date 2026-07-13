"use client";

/**
 * Coordinator layout — provides the auth/session context to every /coordinator
 * page and redirects to /coordinator/login when the user is signed out.
 * Login itself is exempt from the redirect so the form can render.
 */

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { CoordinatorProvider, useCoordinator } from "@/components/coordinator/CoordinatorProvider";

function AuthGuard({ children }) {
  const { me, ready } = useCoordinator();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (!ready) return;
    const isLogin = pathname === "/coordinator/login";
    if (!me && !isLogin) router.replace("/coordinator/login");
    if (me && isLogin) router.replace("/coordinator");
  }, [ready, me, pathname, router]);

  return children;
}

export default function CoordinatorLayout({ children }) {
  return (
    <CoordinatorProvider>
      <AuthGuard>{children}</AuthGuard>
    </CoordinatorProvider>
  );
}
