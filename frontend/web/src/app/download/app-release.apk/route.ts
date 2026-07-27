import { createReadStream, statSync } from "node:fs";
import { Readable } from "node:stream";

import { NextResponse } from "next/server";

/**
 * دانلودِ APKِ اندروید از `dilix.ir/download/app-release.apk`.
 *
 * فایل را `infra/deploy/sync-apk.sh` از artifactِ GitHub Actions می‌آورد و کنارِ
 * سرویسِ `core` می‌گذارد. آوردنش داخلِ `public/` یعنی ۱۱۰+ مگابایت باینری در
 * ریپو و در هر بیلد؛ به‌جایش همان فایلِ روی دیسک stream می‌شود.
 */
const APK_PATH =
  process.env.APK_PATH || "/var/www/dilix-core/outputs/app-release.apk";

export const dynamic = "force-dynamic";

export async function GET() {
  let size: number;
  try {
    size = statSync(APK_PATH).size;
  } catch {
    // هنوز هیچ بیلدی همگام نشده — ۵۰۳ به کاربر می‌گوید بعداً دوباره سر بزند،
    // برخلافِ ۴۰۴ که یعنی چنین چیزی اصلاً وجود ندارد.
    return NextResponse.json(
      { detail: "فایلِ نصبِ اندروید هنوز آماده نیست." },
      { status: 503 },
    );
  }

  const stream = Readable.toWeb(
    createReadStream(APK_PATH),
  ) as ReadableStream<Uint8Array>;

  return new NextResponse(stream, {
    headers: {
      "Content-Type": "application/vnd.android.package-archive",
      "Content-Length": String(size),
      "Content-Disposition": 'attachment; filename="dilix.apk"',
      // با هر همگام‌سازی فایل عوض می‌شود، پس کشِ طولانی نسخهٔ کهنه پخش می‌کرد.
      "Cache-Control": "public, max-age=300",
    },
  });
}
