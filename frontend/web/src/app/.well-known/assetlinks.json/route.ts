import { NextResponse } from "next/server";

/**
 * Digital Asset Links — تأییدِ خودکارِ App Linksِ اندروید.
 *
 * بدونِ این فایل روی `https://dilix.ir`، اندروید ۱۲ به بالا intent-filterِ
 * `autoVerify` را رد می‌کند و لینک‌های `/join`، `/pay/…` و `/earth` باز هم در
 * مرورگر باز می‌شوند (کاربر فقط دستی از تنظیماتِ اپ می‌تواند فعالشان کند).
 *
 * اثرِ انگشتِ گواهیِ امضا از محیط خوانده می‌شود، نه hardcode: کلیدِ امضا با
 * چرخشِ کلید یا مهاجرت به Play App Signing عوض می‌شود و یک مقدارِ اشتباهِ ثابت
 * بدتر از نبودنِ فایل است. تا وقتی `ANDROID_CERT_SHA256` تنظیم نشده، ۴۰۴ می‌دهیم.
 *
 * گرفتنِ اثرِ انگشت:
 *   keytool -list -v -keystore <release.jks> -alias <alias> | grep SHA256
 * چند مقدار (مثلاً کلیدِ آپلود + کلیدِ Play) با کاما جدا می‌شوند.
 */
export const dynamic = "force-dynamic";

const PACKAGE_NAME = "com.dilix.dilix_mobile";

export function GET() {
  const fingerprints = (process.env.ANDROID_CERT_SHA256 ?? "")
    .split(",")
    .map((s) => s.trim().toUpperCase())
    .filter(Boolean);

  if (fingerprints.length === 0) {
    return new NextResponse(null, { status: 404 });
  }

  return NextResponse.json(
    [
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: {
          namespace: "android_app",
          package_name: PACKAGE_NAME,
          sha256_cert_fingerprints: fingerprints,
        },
      },
    ],
    { headers: { "Cache-Control": "public, max-age=3600" } },
  );
}
