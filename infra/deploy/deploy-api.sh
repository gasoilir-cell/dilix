#!/usr/bin/env bash
#
# deploy-api.sh — استقرارِ سرویسِ زنده‌ی `backend/services/api` روی سرور.
#
# چرا اسکریپت و نه `git pull` روی سرور؟ سرور به github.com نمی‌رسد (تایم‌اوت)،
# پس سورس باید از همین محیطِ داخلی هُل داده شود. `rsync` روی سرور نصب نیست،
# پس با `tar | ssh` می‌فرستیم.
#
# آنچه فرستاده نمی‌شود و فقط روی سرور زندگی می‌کند: `.env` (سکرت)، `venv/`
# (۱۸۹MB، از requirements.txt بازسازی می‌شود)، `uploads/` (محتوای کاربر).
#
# متغیرهای محیطی:
#   SERVER       (پیش‌فرض root@185.55.226.250)
#   SERVER_PORT  (پیش‌فرض 22)
#   SERVER_DIR   (پیش‌فرض /var/www/dilix-api)
#   NO_RESTART=1 فقط همگام‌سازی، بدونِ ری‌استارت
#
# نمونه:  ./infra/deploy/deploy-api.sh
set -euo pipefail

SERVER="${SERVER:-root@185.55.226.250}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_DIR="${SERVER_DIR:-/var/www/dilix-api}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/backend/services/api"

[ -d "$SRC/app" ] || { echo "✗ سورس پیدا نشد: $SRC" >&2; exit 1; }

echo "→ همگام‌سازیِ $SRC → $SERVER:$SERVER_DIR"
tar czf - -C "$SRC" \
    --exclude='__pycache__' --exclude='*.pyc' --exclude='.env' \
    --exclude='venv' --exclude='uploads' \
    app alembic alembic.ini requirements.txt \
  | ssh -p "$SERVER_PORT" "$SERVER" "cd '$SERVER_DIR' && tar xzf -"

echo "→ بررسیِ importِ برنامه پیش از ری‌استارت"
# اگر اینجا بشکند سرویسِ در حالِ اجرا دست‌نخورده می‌مانَد و کاربر قطعی نمی‌بیند.
ssh -p "$SERVER_PORT" "$SERVER" \
    "cd '$SERVER_DIR' && venv/bin/python -c 'import app.main' >/dev/null" \
  || { echo "✗ برنامه import نشد — ری‌استارت انجام نشد" >&2; exit 1; }

if [ "${NO_RESTART:-0}" = "1" ]; then
  echo "✓ همگام‌سازی انجام شد (ری‌استارت رد شد)"
  exit 0
fi

echo "→ ری‌استارتِ dilix-api"
ssh -p "$SERVER_PORT" "$SERVER" 'systemctl restart dilix-api && sleep 4 && systemctl is-active dilix-api'

code="$(ssh -p "$SERVER_PORT" "$SERVER" 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/')"
[ "$code" = "200" ] || { echo "✗ سلامتِ سرویس: HTTP $code" >&2; exit 1; }
echo "✓ مستقر شد (HTTP $code)"
