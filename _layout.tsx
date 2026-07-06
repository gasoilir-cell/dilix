import type { Metadata, Viewport } from "next";
import { ThemeProvider } from "next-themes";
import { Toaster } from "react-hot-toast";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Dilix — دیلیکس",
    template: "%s | Dilix",
  },
  description:
    "پلتفرم اتصال جهانی بار، تجارت، بیمه، پرداخت و اکتشاف اجتماعی",
  keywords: ["dilix", "دیلیکس", "حمل بار", "تجارت", "بیمه", "پرداخت"],
  authors: [{ name: "Dilix Team" }],
  manifest: "/manifest.json",
  icons: {
    icon: "/favicon.ico",
    apple: "/apple-touch-icon.png",
  },
  openGraph: {
    type: "website",
    locale: "fa_IR",
    url: "https://dilix.ir",
    siteName: "Dilix",
    title: "Dilix — دیلیکس",
    description: "پلتفرم اتصال جهانی",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0F172A" },
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
  ],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fa" dir="rtl" suppressHydrationWarning>
      <head>
        <link
          rel="preload"
          href="/fonts/Vazirmatn-Regular.woff2"
          as="font"
          type="font/woff2"
          crossOrigin="anonymous"
        />
      </head>
      <body className="font-sans antialiased">
        <ThemeProvider
          attribute="class"
          defaultTheme="dark"
          enableSystem={false}
          disableTransitionOnChange
        >
          {children}
          <Toaster
            position="top-center"
            toastOptions={{
              duration: 4000,
              style: {
                background: "#1E293B",
                color: "#CBD5E1",
                border: "1px solid #334155",
                borderRadius: "12px",
                fontSize: "14px",
                fontFamily: "var(--font-vazir), Tahoma, sans-serif",
                direction: "rtl",
              },
              success: {
                iconTheme: { primary: "#059669", secondary: "#fff" },
              },
              error: {
                iconTheme: { primary: "#DC2626", secondary: "#fff" },
              },
            }}
          />
        </ThemeProvider>
      </body>
    </html>
  );
}
