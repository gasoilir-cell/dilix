"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { getStoredRole, navForRole, onRoleChange } from "@/lib/roles";

const HIDE_ON = ["/login"];

export default function BottomNav() {
  const pathname = usePathname();
  const [role, setRole] = useState<string | null>(null);

  useEffect(() => {
    setRole(getStoredRole());
    return onRoleChange(setRole);
  }, []);

  const items = navForRole(role);
  if (HIDE_ON.some((p) => pathname === p || pathname.startsWith(`${p}/`))) return null;
  return (
    <nav className="bottom-nav" aria-label="ناوبری اصلی">
      {items.map((it) => {
        const active = it.href === "/" ? pathname === "/" : pathname.startsWith(it.href);
        return (
          <Link key={it.href} href={it.href} className={active ? "active" : ""}>
            <span className="ico" aria-hidden>
              {it.icon}
            </span>
            <span>{it.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
