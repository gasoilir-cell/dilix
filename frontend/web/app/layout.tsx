import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";
import BottomNav from "@/components/BottomNav";
import AssistantFab from "@/components/AssistantFab";
import CallManager from "@/components/CallManager";
import { dir } from "@/lib/i18n";

export const metadata: Metadata = {
  title: "Dilix — بستر واسط جهانی",
  description: "اکوسیستم دیجیتال جهانی: ارتباط، حمل‌ونقل، بیمه، مالی و هوش مصنوعی.",
  applicationName: "Dilix",
  manifest: "/manifest.webmanifest",
};

export const viewport: Viewport = {
  themeColor: "#0b1020",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  const locale = "fa" as const;
  return (
    <html lang={locale} dir={dir(locale)}>
      <body>
        <div className="app-shell">
          {children}
          <CallManager />
          <AssistantFab />
        </div>
        <BottomNav />
      </body>
    </html>
  );
}
