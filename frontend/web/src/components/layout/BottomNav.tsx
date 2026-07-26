"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Home, Globe2, MessageCircle, Clapperboard, User } from "lucide-react";
import { useTranslation } from "@/store/i18n";

const NAV = [
  { href:"/dashboard", icon:Home,          tkey:"nav.home",     color:"#6366F1" },
  { href:"/reels",     icon:Clapperboard,  tkey:"nav.reels",    color:"#F43F5E" },
  { href:"/messages",  icon:MessageCircle, tkey:"nav.messages", color:"#10B981" },
  { href:"/earth",     icon:Globe2,        tkey:"nav.earth",    color:"#06B6D4" },
  { href:"/profile",   icon:User,          tkey:"nav.profile",  color:"#A855F7" },
];

export default function BottomNav() {
  const pathname = usePathname();
  const { t } = useTranslation();

  return (
    <nav className="bottom-nav">
      {NAV.map((item) => {
        const active = pathname === item.href ||
          (item.href !== "/dashboard" && pathname.startsWith(item.href));
        const Icon = item.icon;
        return (
          <Link key={item.href} href={item.href}
            className={cn("bottom-nav-item", active && "active")}
            style={active ? { color: item.color } : {}}>
            <div className="relative flex items-center justify-center">
              {active && (
                <div className="absolute inset-0 rounded-xl opacity-15"
                  style={{ background: item.color, transform:"scale(1.8)" }} />
              )}
              <Icon
                className="w-6 h-6 relative z-10 transition-all duration-200"
                style={{ color: active ? item.color : undefined }}
                strokeWidth={active ? 2.5 : 1.8}
              />
            </div>
            <span className="text-[10px] font-medium transition-colors"
              style={{ color: active ? item.color : undefined }}>
              {t(item.tkey)}
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
