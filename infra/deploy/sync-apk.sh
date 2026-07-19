#!/usr/bin/env bash
#
# sync-apk.sh — تازه‌سازیِ خودکارِ APK روی سرورِ Core.
#
# چرا این اسکریپت؟ به‌خاطرِ توپولوژیِ شبکه:
#   • Runnerهای GitHub Actions (بین‌المللی) به سرورِ 185.55.226.250 نمی‌رسند
#     (سرور فقط ترافیکِ داخلیِ ایران را می‌پذیرد) → CI نمی‌تواند مستقیم deploy کند.
#   • خودِ سرور هم به github.com نمی‌رسد (تایم‌اوت) → سرور نمی‌تواند pull کند.
#   • تنها پلی که به هر دو می‌رسد، همین محیطِ داخلیِ اجراست.
# پس این اسکریپت را از همان محیطِ داخلی اجرا کن؛ کارِ آن:
#   ۱) یافتنِ آخرین run موفقِ workflowِ mobile.yml
#   ۲) دانلودِ artifactِ APK از گیت‌هاب (پورت ۴۴۳)
#   ۳) کپیِ APK روی سرور (scp پورت ۲۲) + راستی‌آزماییِ checksum
#
# متغیرهای محیطی:
#   GH_TOKEN     (الزامی) توکنِ دسترسی به گیت‌هاب برای API و دانلودِ artifact
#   GH_REPO      (پیش‌فرض gasoilir-cell/dilix)
#   SERVER       (پیش‌فرض root@185.55.226.250)
#   SERVER_PORT  (پیش‌فرض 22)
#   SERVER_APK   (پیش‌فرض /var/www/dilix-core/outputs/app-release.apk)
#
# نمونه:  GH_TOKEN=xxx ./infra/deploy/sync-apk.sh
set -euo pipefail

GH_REPO="${GH_REPO:-gasoilir-cell/dilix}"
SERVER="${SERVER:-root@185.55.226.250}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_APK="${SERVER_APK:-/var/www/dilix-core/outputs/app-release.apk}"
WORKFLOW="mobile.yml"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "خطا: متغیرِ GH_TOKEN تنظیم نشده است." >&2
  exit 1
fi

api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" "$@"; }

echo "→ یافتنِ آخرین runِ موفقِ ${WORKFLOW} ..."
RUN_ID=$(api "https://api.github.com/repos/${GH_REPO}/actions/workflows/${WORKFLOW}/runs?status=success&per_page=1" \
  | python3 -c "import sys,json;r=json.load(sys.stdin)['workflow_runs'];print(r[0]['id'] if r else '')")
[[ -n "${RUN_ID}" ]] || { echo "خطا: هیچ runِ موفقی یافت نشد." >&2; exit 1; }
echo "  run id = ${RUN_ID}"

echo "→ یافتنِ artifactِ APK ..."
ART_URL=$(api "https://api.github.com/repos/${GH_REPO}/actions/runs/${RUN_ID}/artifacts" \
  | python3 -c "import sys,json;a=[x for x in json.load(sys.stdin)['artifacts'] if not x['expired']];print(a[0]['archive_download_url'] if a else '')")
[[ -n "${ART_URL}" ]] || { echo "خطا: artifactِ سالمی یافت نشد (شاید منقضی شده)." >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
echo "→ دانلودِ artifact ..."
curl -sSL -H "Authorization: Bearer ${GH_TOKEN}" "${ART_URL}" -o "${TMP}/apk.zip"
python3 -c "import zipfile,sys; zipfile.ZipFile('${TMP}/apk.zip').extractall('${TMP}')"
APK="${TMP}/app-release.apk"
[[ -f "${APK}" ]] || { echo "خطا: app-release.apk در artifact نبود." >&2; exit 1; }
LOCAL_SHA=$(sha256sum "${APK}" | awk '{print $1}')
echo "  local sha256 = ${LOCAL_SHA}  ($(stat -c%s "${APK}") bytes)"

echo "→ کپی روی سرور (${SERVER}:${SERVER_APK}) ..."
ssh -o StrictHostKeyChecking=no -p "${SERVER_PORT}" "${SERVER}" "mkdir -p \"\$(dirname '${SERVER_APK}')\""
scp -o StrictHostKeyChecking=no -P "${SERVER_PORT}" "${APK}" "${SERVER}:${SERVER_APK}"

REMOTE_SHA=$(ssh -o StrictHostKeyChecking=no -p "${SERVER_PORT}" "${SERVER}" "sha256sum '${SERVER_APK}' | awk '{print \$1}'")
echo "  remote sha256 = ${REMOTE_SHA}"
if [[ "${LOCAL_SHA}" == "${REMOTE_SHA}" ]]; then
  echo "✓ همگام‌سازی موفق. endpoint: http://185.55.226.250:8010/download/app-release.apk"
else
  echo "خطا: checksum سرور با نسخهٔ محلی نمی‌خواند." >&2
  exit 1
fi
