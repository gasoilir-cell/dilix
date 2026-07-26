# dilix-web — اپِ زنده‌ی وب (production)

**این همان چیزی است که کاربر امروز در مرورگر می‌بیند.** روی سرور در
`/var/www/dilix` می‌نشیند، با `dilix.service` روی پورت **۳۰۰۳** اجرا می‌شود و
به `dilix-api` (پورت ۸۰۰۰، پیشوندِ `/api/v1`) وصل است.

## چرا این پوشه بازنویسی شد

تا امروز اینجا یک **نمونهٔ اولیهٔ متروک** بود: نسلی قدیمی‌تر با `app/` تخت،
سه وابستگی و چند تستِ `*.test.mjs` — چیزی که هیچ‌کجا سرو نمی‌شد و با اپِ واقعی
هم‌خانواده نبود. سورسِ اپِ واقعی فقط روی سرور بود و **زیرِ هیچ کنترلِ نسخه‌ای
نبود**؛ تنها «تاریخچه»‌اش ۸۴ فایلِ `*.bak-<timestamp>` بود که کنارِ هر ویرایشِ
دستی ساخته می‌شد. حالا سورسِ واقعی اینجاست و آن بکاپ‌ها وارد نشدند — گیت
جایشان را گرفته است.

همان کاری که پیش‌تر برای [`backend/services/api`](../../backend/services/api)
انجام شد.

## ساختار

```
src/
  app/
    (auth)/          # login, register, verify, onboarding
    (main)/          # earth, discover, messages, reels, live, wallet, u/[earthId], ...
    globe-tiles/     # سرو کاشیِ کرهٔ زمین
    join/            # لینکِ دعوت
  components/        # auth, call, chat, earth, feed, freight, live, reels, layout, ui
  lib/api.ts         # کلاینتِ dilix-api
  lib/i18n.ts        # جدولِ ترجمه (بزرگ‌ترین فایلِ سورس)
  store/             # zustand
public/libs/         # globe.gl, three.js, maplibre, geojson — عمداً vendor شده،
                     # چون CDNهای عمومی از ایران قابلِ اتکا نیستند
deploy.sh            # بیلد + کپیِ static/public در standalone + ری‌استارت
```

## استقرار

```bash
# از ریشهٔ مخزن
./infra/deploy/deploy-web.sh
```

سورس فرستاده می‌شود، `type-check` روی سرور اجرا می‌شود و تنها در صورتِ موفقیت
`deploy.sh`ِ سرور بیلد و ری‌استارت می‌کند. آنچه **عمداً منتقل نمی‌شود**:

| مورد | چرا |
|---|---|
| `.env.local` | پیکربندیِ محیط. الگو: [`.env.example`](.env.example) |
| `node_modules/` | ۶۸۷ مگابایت؛ از `package.json` بازسازی می‌شود |
| `.next/` | فرآوردهٔ بیلد (۱.۵ گیگ) |

## نکته‌های عملیاتی

- سرویس: `systemctl {status,restart} dilix` · لاگ: `journalctl -u dilix -f`
- خروجی `output: "standalone"` است. پس از هر بیلد باید `.next/static` و
  `public/` **دستی** داخلِ `.next/standalone` کپی شوند، وگرنه همهٔ چانک‌های
  `/_next/static/*` با ۴۰۴ می‌خورند و صفحه روی اسپلش گیر می‌کند. `deploy.sh`
  همین کار را می‌کند.
- `package-lock.json` روی سرور **وجود نداشت**، یعنی هر `npm install` می‌توانست
  نسخه‌ی متفاوتی از `^`ها بیاورد و بیلد بازتولیدپذیر نبود. حالا قفلی کامیت شده
  که دقیقاً روی نسخه‌های در حالِ اجرا در production قفل است (`next 15.1.3`،
  `react 19.2.7`، …) و `npm ci` آن را می‌پذیرد. پس **از این پس `npm ci`** نه
  `npm install` — وگرنه دوباره جابه‌جا می‌شود.
- روی همین سرور چند اپِ Next.js دیگر (`bds`، `earth365`، `hoovar`) روی
  پورت‌های ۳۰۰۰–۳۰۰۲ اجرا می‌شوند و **به Dilix ربطی ندارند**؛ سرویسِ ما فقط
  `dilix.service` روی ۳۰۰۳ است.
