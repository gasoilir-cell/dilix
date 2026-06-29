"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const items = [
  { href: "/", icon: "🏠", key: "nav_home", label: "خانه" },
  { href: "/earth", icon: "🌍", key: "nav_earth", label: "کره" },
  { href: "/messages", icon: "💬", key: "nav_messages", label: "پیام‌ها" },
  { href: "/services", icon: "🧩", key: "nav_services", label: "خدمات" },
  { href: "/me", icon: "👤", key: "nav_me", label: "من" },
];

const HIDE_ON = ["/login"];

export default function BottomNav() {
  const pathname = usePathname();
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
