#!/usr/bin/env bash
#
# deploy-web.sh — استقرارِ اپِ زنده‌ی وب (`frontend/web`) روی سرور.
#
# همان الگوی `deploy-api.sh`: سرور به github.com نمی‌رسد و `rsync` ندارد، پس
# سورس با `tar | ssh` از همین محیط هُل داده می‌شود.
#
# آنچه فرستاده نمی‌شود و فقط روی سرور زندگی می‌کند: `.env.local` (کلیدهای
# عمومیِ ورودِ اجتماعی)، `node_modules/` و `.next/` (فرآوردهٔ بیلد).
#
# بیلد **روی سرور** اجرا می‌شود، نه اینجا: سیاستِ پروژه بیلدِ سنگین را داخلِ
# کانتینر ممنوع می‌کند و خروجیِ `standalone` هم باید کنارِ همان Node‌ای ساخته
# شود که اجرایش می‌کند.
#
# متغیرهای محیطی:
#   SERVER       (پیش‌فرض root@185.55.226.250)
#   SERVER_PORT  (پیش‌فرض 22)
#   SERVER_DIR   (پیش‌فرض /var/www/dilix)
#   NO_BUILD=1   فقط همگام‌سازی، بدونِ بیلد و ری‌استارت
#
# نمونه:  ./infra/deploy/deploy-web.sh
set -euo pipefail

SERVER="${SERVER:-root@185.55.226.250}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_DIR="${SERVER_DIR:-/var/www/dilix}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/frontend/web"

[ -d "$SRC/src/app" ] || { echo "✗ سورس پیدا نشد: $SRC" >&2; exit 1; }

echo "→ همگام‌سازیِ $SRC → $SERVER:$SERVER_DIR"
tar czf - -C "$SRC" \
    --exclude='node_modules' --exclude='.next' --exclude='.env.local' \
    --exclude='tsconfig.tsbuildinfo' --exclude='*.bak-*' \
    src public package.json package-lock.json next.config.ts next-env.d.ts \
    postcss.config.js tailwind.config.ts tsconfig.json deploy.sh \
  | ssh -p "$SERVER_PORT" "$SERVER" "cd '$SERVER_DIR' && tar xzf -"

echo "→ بررسیِ نوع‌ها پیش از بیلد"
# ارزان‌تر از یک بیلدِ کامل و خطای تایپ را پیش از آنکه سرویس را لمس کنیم می‌گیرد.
ssh -p "$SERVER_PORT" "$SERVER" "cd '$SERVER_DIR' && npm run type-check" \
  || { echo "✗ type-check شکست — بیلد انجام نشد" >&2; exit 1; }

if [ "${NO_BUILD:-0}" = "1" ]; then
  echo "✓ همگام‌سازی انجام شد (بیلد رد شد)"
  exit 0
fi

# `deploy.sh`ِ خودِ سرور: بیلد، کپیِ static/public داخلِ standalone (بدونِ آن
# همه‌ی چانک‌ها ۴۰۴ می‌شوند)، ری‌استارت و smoke test.
echo "→ بیلد و ری‌استارت روی سرور"
ssh -p "$SERVER_PORT" "$SERVER" "cd '$SERVER_DIR' && bash deploy.sh"

code="$(ssh -p "$SERVER_PORT" "$SERVER" 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/')"
[ "$code" = "200" ] || { echo "✗ سلامتِ سرویس: HTTP $code" >&2; exit 1; }
echo "✓ مستقر شد (HTTP $code)"
