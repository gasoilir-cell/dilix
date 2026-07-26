#!/usr/bin/env bash
# دیپلوی استاندالون Next.js برای Dilix.
# نکته حیاتی: در حالت output:"standalone" باید بعد از build پوشه‌های
# static و public دستی داخل .next/standalone کپی شوند وگرنه همه چانک‌های
# /_next/static/* با 404 مواجه می‌شوند و صفحه در سمت کلاینت لود نمی‌شود
# (اسپلش برای همیشه گیر می‌کند).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> next build"
npm run build

echo "==> copy static + public into standalone"
rm -rf .next/standalone/.next/static
cp -r .next/static .next/standalone/.next/static
if [ -d public ]; then
  rm -rf .next/standalone/public
  cp -r public .next/standalone/public
fi

echo "==> restart dilix.service"
systemctl restart dilix.service
sleep 2
systemctl is-active dilix.service

echo "==> smoke test"
C=$(curl -s http://127.0.0.1:3003/ | grep -oE "/_next/static/chunks/webpack-[a-z0-9]+\.js" | head -1)
curl -s -o /dev/null -w "root:%{http_code} chunk:%{http_code}\n" \
  http://127.0.0.1:3003/ && \
curl -s -o /dev/null -w "chunk %s : %{http_code}\n" "$C" http://127.0.0.1:3003"$C"
echo "==> done"
