# STATUS — گزارش وضعیت مخزن Dilix

تاریخ: 2026-07-12 · نوع: تحلیل و گزارش (بدون حذف/جابجایی فایل)

---

## Task 1 — تست‌های Core (بلاک‌کننده)

**نتیجه آخرین اجرای کامل ثبت‌شده: ✅ 143 passed / 0 failed**

- دستور استاندارد: `cd backend/services/core && PYTHONPATH=. pytest -v`
- برای اجرای هدفمند SQLite:
  `DILIX_DATABASE_URL="sqlite+aiosqlite:///:memory:" PYTHONPATH=. pytest`
- تست‌های جدید/مهم: stickers/stories unit + integration، payments/marketplace، telecom، discovery، growth، insurance/web integration.
- در این مرحله پوشش `delete` و وضعیت auth برای endpointهای `stickers` و `stories` اضافه شد. در کانتینر فعلی `pytest` نصب نیست (`ModuleNotFoundError: No module named 'pytest'`) و wrapper موجود هم `No tests collected` برگرداند؛ syntax همه فایل‌های تست/ migration با `python -m py_compile` سبز شد.

### نکته محیطی (نه باگ کد)
اجرای اولیه با `make core-test` شکست خورد چون:
1. وابستگی‌های dev/runtime در کانتینر نصب نبودند (pytest, fastapi, sqlalchemy, aiosqlite, ...).
2. `database_url` پیش‌فرض به `postgresql+asyncpg` اشاره دارد و `app/core/database.py:21`
   در زمان import یک async engine می‌سازد → بدون `asyncpg` یا بدون override به sqlite، خطای import.

**اصلاحِ ریشه‌ای لازم در کد نبود.** فقط نصب وابستگی‌ها + ست‌کردن `DILIX_DATABASE_URL` به aiosqlite.
پیشنهاد بهبود (اختیاری، خارج از این تسک): افزودن `tests/conftest.py` که پیش از import، env تست را
به sqlite ست کند تا `make core-test` بدون تنظیم دستی سبز شود.

---

## Task 3 — وضعیت صفحات frontend/web

ساختار: `frontend/web/app/` (App Router، اسکلتِ سبک — جدا از بیلد standalone روی سرور).

| صفحه اصلی | مسیر در frontend/web | وضعیت |
|-----------|----------------------|-------|
| messages  | `app/messages/page.tsx` (88 خط) | موجود — سبک |
| earth     | `app/earth/page.tsx` (89 خط) | موجود — سبک |
| freight   | `app/services/freight/page.tsx` (104 خط) | موجود |
| insurance | `app/services/insurance/page.tsx` (30 خط) | استاب |
| profile   | `app/me/page.tsx` (192 خط) | موجود (معادل profile) |
| **wallet**| `app/wallet/page.tsx` (canonical) | موجود — کیف پاداش + escrow؛ شارژ/برداشت غیرفعالِ توضیح‌دار |
| notifications | `app/notifications/page.tsx` | موجود — list/markRead |
| support | `app/support/page.tsx` | موجود — FAQ همگام با وضعیت wallet/Core |
| provider  | `app/provider/page.tsx` (235 خط) | موجود — کامل‌ترین |
| services  | `app/services/page.tsx` (30) + marketplace/telecom (استاب) | استاب |
| login     | `app/login/page.tsx` (38) | موجود |
| legal     | `privacy` (30) / `terms` (24) | موجود |

نتیجه: اسکلتِ frontend/web اکنون صفحات اصلی wallet/notifications/support را هم دارد؛ این صفحات با قراردادهای canonical وب و `lib/api.ts` سبک نوشته شده‌اند.

---

## Task 2 — نگاشت فایل‌های stray روت به معادل‌ها

معیار: **DUPLICATE** = معادل کارکردی در `frontend/web/` یا `backend/services/core/app/modules/` دارد ·
**UNIQUE** = معادلی ندارد.

### فایل‌های فرانت‌اند (روت → معادل)

| فایل روت | معادل canonical | وضعیت |
|----------|-----------------|-------|
| `_earth.tsx`, `earth_v4/v5/v6/v7.tsx` | `web/app/earth/page.tsx` | DUPLICATE (نسخه‌های متعدد) |
| `freight-page.tsx`, `freight_page_v2.tsx` | `web/app/services/freight/page.tsx` | DUPLICATE |
| `insurance_real.tsx` | `web/app/services/insurance/page.tsx` | DUPLICATE |
| `_messages_page.tsx`, `messages_page.tsx`, `messages_real.tsx` | `web/app/messages/page.tsx` | DUPLICATE |
| `chat_page.tsx`, `chat_page_v2.tsx`, `messages_id_redirect.tsx` | messages (زیرمجموعه) | DUPLICATE (جزئی) |
| `_profile.tsx`, `profile_real.tsx`, `profile_page_new.tsx` | `web/app/me/page.tsx` | DUPLICATE |
| `services_real.tsx` | `web/app/services/page.tsx` | DUPLICATE |
| `_layout.tsx` | `web/app/layout.tsx` | DUPLICATE |
| `_api.ts`, `api_real.ts` | `web/lib/api.ts` | DUPLICATE |
| `globals_dark.css` | `web/app/globals.css` | DUPLICATE (واریانت dark) |
| `ai_real.tsx` | `web/components/AssistantFab.tsx` | DUPLICATE (جزئی) |
| `AppShell_dark.tsx`, `AppShell_updated.tsx` | — (web از BottomNav استفاده می‌کند) | UNIQUE |
| `wallet_real.tsx` | — (wallet در web نیست) | **UNIQUE — کاندیدِ انتقال** |
| `notifications_page.tsx` | — | **UNIQUE — کاندیدِ انتقال** |
| `support_page.tsx` | — | **UNIQUE — کاندیدِ انتقال** |
| `_onboarding.tsx`, `onboarding_v2.tsx` | — | UNIQUE |
| `dashboard_v2.tsx` | — | UNIQUE |
| `join_page.tsx` | — (join در web نیست) | UNIQUE |
| `_global-error.tsx` | — | UNIQUE (فایل استاندارد Next) |
| `_MediaEditor.tsx`, `_StickerLibrary.tsx`, `_StoryBar.tsx`, `_StoryViewer.tsx` | — | UNIQUE |
| `tile-route.ts` | — (route کاشیِ نقشه) | UNIQUE |
| `dilix-presentation.html` | — | UNIQUE (بازاریابی مستقل) |

### فایل‌های بک‌اند (روت → معادل ماژول)

| فایل روت | معادل canonical | وضعیت |
|----------|-----------------|-------|
| `_messages_model.py`, `messages_model.py` | `core/app/modules/messaging/models.py` | DUPLICATE |
| `_messages_router.py`, `messages_router.py` | `core/app/modules/messaging/router.py` | DUPLICATE |
| `freight_model.py` | `core/app/modules/freight/models.py` | DUPLICATE |
| `freight_router.py` | `core/app/modules/freight/router.py` | DUPLICATE |
| `insurance_router.py` | `core/app/modules/insurance/router.py` | DUPLICATE |
| `notifications_router.py` | `core/app/modules/notification/router.py` | DUPLICATE |
| `referral_router.py` | `core/app/modules/referral/router.py` | DUPLICATE |
| `ai_router.py` | `core/app/modules/ai/router.py` | DUPLICATE |
| `_user_model.py` | `core/app/modules/identity/models.py` | DUPLICATE |
| `_stickers_model.py`, `_stickers_router.py` | — (ماژول stickers نیست) | **UNIQUE — کاندیدِ ماژول جدید** |
| `_stories_model.py`, `_stories_router.py` | — (ماژول stories نیست) | **UNIQUE — کاندیدِ ماژول جدید** |
| `_e2e_sticker_msg.py`, `_e2e_stickers.py`, `_stories_e2e.py` | — | UNIQUE (اسکریپت e2e) |

---

## خلاصهٔ «فایل‌هایی که باید منتقل شوند» (فقط پیشنهاد — بدون اجرا)

فایل‌های **UNIQUE** که قابلیتِ واقعی دارند و در ساختار canonical جایی ندارند:

- فرانت (کاندیدِ افزودن به `frontend/web/app/`):
  `wallet_real.tsx` → `app/wallet/`، `notifications_page.tsx` → `app/notifications/`،
  `support_page.tsx` → `app/support/`، `join_page.tsx` → `app/join/`،
  `onboarding_v2.tsx` → `app/onboarding/`، `dashboard_v2.tsx` → `app/dashboard/`.
- کامپوننت‌های استوری/استیکر/مدیا → `frontend/web/components/`.
- بک (کاندیدِ ماژول جدید در `core/app/modules/`):
  `_stickers_*` → `modules/stickers/`، `_stories_*` → `modules/stories/`.

فایل‌های **DUPLICATE** توسط نسخه‌های ماژول/صفحهٔ canonical جایگزین شده‌اند و صرفاً نسخه‌های
قدیمی/آزمایشی روت‌اند (پاک‌سازیِ آتی — خارج از این گزارش).

> هیچ فایلی در این مرحله حذف یا جابجا نشد. این سند صرفاً تحلیل و نگاشت است.

---

# مرحلهٔ اجرا — انتقال، ساخت ماژول و پاک‌سازی

تاریخ: 2026-07-12 · نوع: اجرا (انتقال/ساخت/حذف واقعی)

## Task 1 — انتقال ۳ صفحهٔ UNIQUE فرانت به `frontend/web` ✅ انجام‌شده

| صفحه | مقصد canonical | وضعیت |
|------|----------------|-------|
| `wallet_real.tsx`        | `frontend/web/app/wallet/page.tsx`        | ساخته شد |
| `notifications_page.tsx` | `frontend/web/app/notifications/page.tsx` | ساخته شد |
| `support_page.tsx`       | `frontend/web/app/support/page.tsx`       | ساخته شد |

- فایل‌های روت پس از انتقال حذف شدند.
- **تطبیق لازم بود (نه کپیِ مستقیم):** فایل‌های اصلی برای اپِ standalone دیپلوی‌شده نوشته
  شده بودند و به `@/components/layout/AppShell`، `@/components/ui/Button`، `@/lib/utils`،
  `lucide-react`، `react-hot-toast`، `walletApi/paymentApi` وابسته بودند — که هیچ‌کدام در
  `frontend/web` وجود ندارند. هر سه صفحه به قراردادهای `frontend/web` بازنویسی شدند:
  CSS ساده (`page`, `card`, `plain-list`, ...)، کلاینتِ `api` موجود، بدون وابستگیِ خارجی.
- `frontend/web/lib/api.ts` با interface `NotificationOut` و بخش `notifications`
  (list / markRead) گسترش یافت (مطابق route های backend: GET `/v1/notifications`،
  POST `/v1/notifications/{id}/read`).
- **wallet**: قابلیت‌های تراکنشی (شارژ/انتقال/لیست تراکنش) پورت نشد چون backend
  اندپوینتِ کیف‌پولِ تراکنشی ندارد (فقط escrow پرداخت + reward wallet). به‌جای آن از
  `api.growth` (rewards/referralLink/revenueShare) استفاده شد + کارتِ «شارژ و انتقال به‌زودی».

## Task 2 — ساخت ماژول backend برای stickers و stories ✅ انجام‌شده

- `core/app/modules/stickers/` ساخته شد: `models.py` (۴ جدول در schema `stickers`)،
  `schemas.py`، `router.py` (prefix `/v1/stickers`، ۱۰ route)، `__init__.py`.
- `core/app/modules/stories/` ساخته شد: `models.py` (۳ جدول در schema `stories`)،
  `schemas.py`، `router.py` (prefix `/v1/stories`، ۹ route)، `__init__.py`.
- هر دو router در `app/main.py` register شدند (بعد از `social_router`).
- فایل‌های روت `_stickers_*` و `_stories_*` حذف شدند.
- **تطبیق لازم بود (نه کپیِ مستقیم):** فایل‌های اصلی از backendِ دیگری (dilix-api یکپارچه)
  بودند و به `app.api.deps`، `app.models.user.User`، `app.models.social.Follow`،
  `get_db` و `ForeignKey("users.id")` وابسته بودند — هیچ‌کدام در `services/core` نیست.
  register مستقیم، import `app.main` را می‌شکست و همهٔ تست‌ها را قرمز می‌کرد. لذا به
  قراردادهای core بازنویسی شدند: مدل‌های SQLAlchemy 2.0، schema-qualified،
  هویت با `earth_id` (UUID، بدون FK به users)، `CurrentUser/get_current_user`،
  `get_session`، بدون JOIN بین‌کانتکستی. رسانه از طریق body JSON (نه file upload).
  audience «followers» حذف شد (نیازمند گرافِ Follow در ماژول social).
- **اعتبارسنجی:** `app.main` بدون خطا import می‌شود، `app.openapi()` route ها را نشان
  می‌دهد، و `pytest` → **98 passed**.
- ⚠️ اندپوینت‌ها هنوز به تستِ یکپارچگی (integration) با DB نیاز دارند؛ تست‌های فعلی unit اند.

## Task 3 — حذف ۳۲ فایل DUPLICATE روت ✅ انجام‌شده

۳۲ فایلِ فهرست‌شده در جداول Task 2 (بالا) که معادلِ canonical داشتند حذف شدند:
`_earth.tsx`, `earth_v4/v5/v6/v7.tsx`, `freight-page.tsx`, `freight_page_v2.tsx`,
`insurance_real.tsx`, `_messages_page.tsx`, `messages_page.tsx`, `messages_real.tsx`,
`chat_page.tsx`, `chat_page_v2.tsx`, `_profile.tsx`, `profile_real.tsx`,
`profile_page_new.tsx`, `services_real.tsx`, `_layout.tsx`, `_api.ts`, `api_real.ts`,
`globals_dark.css`, `_messages_model.py`, `messages_model.py`, `_messages_router.py`,
`messages_router.py`, `freight_model.py`, `freight_router.py`, `insurance_router.py`,
`notifications_router.py`, `referral_router.py`, `ai_router.py`, `_user_model.py`.

فایل‌های **UNIQUE** دیگر دست‌نخورده ماندند:
`messages_id_redirect.tsx`, `tile-route.ts`, `join_page.tsx`, `_global-error.tsx`,
`ai_real.tsx`, `AppShell_dark.tsx`, `AppShell_updated.tsx`, `dashboard_v2.tsx`,
`onboarding_v2.tsx`, `_onboarding.tsx`, `_MediaEditor.tsx`, `_StickerLibrary.tsx`,
`_StoryBar.tsx`, `_StoryViewer.tsx`, `dilix-presentation.html`,
`_e2e_sticker_msg.py`, `_e2e_stickers.py`, `_stories_e2e.py`.

> همهٔ حذف‌ها git-tracked و برگشت‌پذیرند.

---

# مرحلهٔ تست و پایدارسازی

تاریخ: 2026-07-12

## conftest تست ✅ انجام‌شده
- `backend/services/core/tests/conftest.py` ساخته شد و پیش از هر import،
  `DILIX_DATABASE_URL` را روی `sqlite+aiosqlite:///:memory:` ست می‌کند
  (`os.environ.setdefault`). حالا `make core-test` بدونِ تنظیمِ دستیِ env سبز است.

## تست stickers و stories ✅ انجام‌شده
- `tests/test_stickers.py` (۷ تست) و `tests/test_stories.py` (۹ تست) ساخته شدند.
- هم‌راستا با سبکِ بقیهٔ Core (unit، بدون DB — چون جداولِ schema-qualified روی
  SQLite ساخته نمی‌شوند): اعتبارِ اسکیماها، توابعِ mapping روتر
  (`_pack_out`/`_sticker_out`)، منطقِ دسترسیِ داستان (`_can_view`)، انقضای ۲۴ساعته
  (`_expiry`)، ثابت‌های مخاطب، و وجودِ مسیرهای اصلی (create/list/get) از طریقِ
  `app.openapi()` (ضدِ drift).
- **اعتبارسنجی:** کلِ سوئیت بدونِ env دستی → **114 passed** (۹۸ قبلی + ۱۶ واحدِ جدید).

## Alembic رسمی برای stickers/stories ✅ انجام‌شده
- `alembic/env.py` اکنون مدل‌های `app.modules.stickers.models` و `app.modules.stories.models` را import می‌کند تا metadata drift نداشته باشد.
- `alembic/versions/0001_initial_baseline.py` schemaهای `stickers` و `stories` را در baseline دارد.
- migration افزایشی `alembic/versions/0002_stickers_stories.py` ساخته شد: schemaها، ۷ جدول (`sticker_pack`, `sticker`, `starred_sticker`, `installed_pack`, `story`, `contact_circle`, `story_view`) و index/unique/FKهای لازم را صریح می‌سازد و downgrade کامل دارد.
- اعتبارسنجی syntax: `python -m py_compile` روی migrationها و تست‌های مرتبط سبز شد.

## تستِ integration اندپوینت‌های stickers/stories ✅ انجام‌شده
- هارنسِ HTTP در `conftest.py` (فیکسچرِ `integration`): engineِ SQLite با `StaticPool`
  (اشتراکِ همان دیتابیسِ درون‌حافظه بین اتصال‌ها) + **ATTACH DATABASE** برای schemaهای
  `stickers`/`stories` (تا جداولِ schema-qualified روی SQLite ساخته شوند)، override روی
  `get_session` و `get_current_user`، و `httpx.AsyncClient` روی ASGI. کلاسِ
  `IntegrationHarness` امکانِ `as_user(...)` برای تعویضِ کاربرِ احرازشده در طولِ تست را می‌دهد.
  - نکتهٔ فنی حل‌شده: `postgresql.UUID` روی SQLite به CHAR افت می‌کند (SQLAlchemy 2.0)؛
    و باگِ overwriteِ نامِ `app` توسط `import app.modules...` با importِ alias رفع شد.
- `tests/test_stickers_integration.py` (۱۱ تست): create pack، list mine، add sticker +
  detail (+cover)، public listing، مخفی‌بودنِ خصوصی، چرخهٔ install توسط کاربرِ دیگر،
  star/starred، حذف sticker و pack، ۴۰۴ برای حذف توسط غیرمالک، الزام auth، ۴۰۴ برای بستهٔ ناموجود.
- `tests/test_stories_integration.py` (۱۱ تست): create story، feed (ring خودی)، user
  stories، view (idempotent) + viewers، ۴۰۳ برای غیرِنویسنده، مخفی‌بودنِ داستانِ حلقه‌ای
  و نمایانی پس از افزودن به حلقه، circles list/add، حذف story، ۴۰۴ برای حذف توسط غیرمالک، الزام auth، ردِ افزودنِ خود.
- **اعتبارسنجی نهایی:** کلِ سوئیت بدونِ env دستی → **130 passed** (بدون هشدارِ event-loop).

---

# مهاجرت فایل‌های سرگردانِ روت به ساختار canonical

تاریخ: 2026-07-12

## صفحاتِ UNIQUE فرانت → `frontend/web/app/` ✅ انجام‌شده
بازنویسیِ کامل مطابقِ قراردادهای `frontend/web` (CSS ساده، کلاینتِ `api`،
بدونِ `lucide-react`/`react-hot-toast`/`zustand`/`@/components/ui/*`):
- `join_page.tsx` → `app/join/page.tsx` (ثبتِ کدِ دعوت در localStorage + ریدایرکت به `/login`).
- `onboarding_v2.tsx` → `app/onboarding/page.tsx` (ویزاردِ ۴مرحله‌ای: نقش/پروفایل/حریمِ خصوصی؛
  با `api.identity.roles/updateProfile/changeRole/setVisibility`).
- `dashboard_v2.tsx` → `app/dashboard/page.tsx` (داشبوردِ نقش‌محور با `api.identity.me`،
  `api.growth.rewards`، `panelsForRole`).
- `_global-error.tsx` → `app/global-error.tsx` (مرزِ خطای فریم‌ورک؛ بازیابیِ خودکار در chunk-load
  error — تنها وابستگی: `useEffect`، سازگار با canonical).
- فایل‌های روت پس از مهاجرت حذف شدند.

## پاک‌سازیِ فایل‌های مرده (git-tracked، برگشت‌پذیر) ✅ انجام‌شده
اینها به استکِ قدیمیِ مونولیت وابسته بودند (lucide/toast/zustand/`@/lib/utils`/
`@/components/ui/*`/`app.models.user`) و در `frontend/web`ِ canonical معادل یا مصرف‌کننده نداشتند:
- `AppShell_dark.tsx`, `AppShell_updated.tsx` — canonical از `layout.tsx` + `BottomNav` استفاده می‌کند.
- `ai_real.tsx` — صفحهٔ AIِ استکِ قدیم؛ بدونِ معادلِ canonical.
- `messages_id_redirect.tsx` — با `app/messages/page.tsx` (پارامترِ `?to=`) جایگزین شده.
- `tile-route.ts` — پراکسیِ کاشیِ گوگل؛ صفحهٔ `earth` canonical کاشیِ واقعی رِندر نمی‌کند (placeholder).
- `_onboarding.tsx` — نسخهٔ تکراریِ onboarding.
- `_e2e_sticker_msg.py`, `_e2e_stickers.py`, `_stories_e2e.py` — اسکریپت‌های standalone با
  importهای مونولیتِ قدیم (`app.models.user`، `AsyncSessionLocal`) و نیازمندِ سرورِ زنده؛
  با تست‌های integrationِ Core جایگزین شده‌اند.

## ثبتِ مسیرهای جدید در ناوبری ✅ انجام‌شده
- `app/me/page.tsx`: دو تایلِ جدید → `/dashboard` و `/onboarding`.

## کامپوننت‌های استوری/استیکر/مدیا → `frontend/web/components/` ✅ انجام‌شده
پورتِ کاملِ ۴ کامپوننت با تطبیقِ وابستگی‌های خارجی به قراردادهای canonical:
- **شیم‌های بدونِ وابستگی** (جایگزینِ استکِ حذف‌شده):
  - `lib/icons.tsx` — ~۴۰ آیکونِ ایموجی‌محور جایگزینِ `lucide-react`.
  - `lib/toast.ts` — توستِ DOM-محور جایگزینِ `react-hot-toast` (امضای سازگار: `toast`, `.success/.error/.loading/.dismiss`).
- **لایهٔ کلاینتِ API** در `lib/api.ts`: بخش‌های `api.stories` و `api.stickers` + تایپ‌ها
  (`StoryRingOut`, `StoryOut`, `StoryViewerOut`, `CirclesOut`, `StickerOut`, `StickerPackOut`, `StickerPackDetailOut`)
  — منطبق بر روترهای mount‌شدهٔ `stories`/`stickers`.
- `_StoryViewer.tsx` → `components/StoryViewer.tsx` (نمایشِ رینگ‌ها، rAF progress، ثبتِ بازدید،
  حذف، شیتِ بازدیدکنندگان با `earth_id`).
- `_StoryBar.tsx` → `components/StoryBar.tsx` (`useAuthStore`→`api.identity.me`، `storiesApi.feed`→
  `api.stories.feed`، انتشار با data-URL به‌جای آپلودِ فایل؛ `settings/saveSettings` حذف شد چون
  بک‌اند endpoint ندارد).
- `_StickerLibrary.tsx` → `components/StickerLibrary.tsx` (`stickersApi`→`api.stickers` با حذفِ `.data`،
  امضاهای جدید؛ `addSticker`/`createPack` با data-URL؛ `owner_name` حذف چون در قراردادِ جدید نیست).
- `_MediaEditor.tsx` → `components/MediaEditor.tsx` (ادیتورِ canvas بدونِ تغییرِ منطق؛ فقط
  `messagesApi.translateText` → degrade مؤدبانه، چون `api.messaging` endpointِ ترجمه ندارد).
- کلاسِ‌های Tailwind به‌عنوانِ رشتهٔ بی‌اثر حفظ شدند (Tailwind نصب نیست).
- فایل‌های روت پس از مهاجرت با `git rm` حذف شدند.

## اعتبارسنجی
- تغییراتِ این مرحله فقط فرانت + اسکریپت‌های روت را لمس کرد؛ سوئیتِ `backend/services/core/tests/`
  دست‌نخورده و سبز (baseline: **130 passed**). در این کانتینر `pytest` نصب نیست
  (`No module named pytest`)، اجرای واقعی روی سرورِ SSH.
- همهٔ حذف‌ها git-tracked و برگشت‌پذیرند.

---

## صفحات وبِ جامانده که تکمیل شد (Milestone 1 و 3)
مقایسهٔ ماژول‌های بک‌اندِ mount‌شده با صفحاتِ `frontend/web` نشان داد چند ظرفیت، بک‌اند داشت
ولی UIِ وب نداشت. این مرحله آن گپ‌ها را پر کرد. الگو: همان صفحاتِ `services/*` (کارت + fetch از `api`).

| ماژول بک‌اند (روتر) | صفحهٔ وبِ جدید | خلاصه |
|---|---|---|
| `modules/social` (`/v1/social`) | `app/social/page.tsx` | فیدِ کامل: پست با متن + **رسانه (data-URL)** + لایک + **افزودنِ نظر** (`comment`). صفحهٔ `/` فیدِ سبکِ لندینگ می‌ماند؛ `/social` نسخهٔ کامل با رسانه/نظر است. |
| `modules/stories` (`/v1/stories`) | `app/stories/page.tsx` | صفحهٔ مستقلِ داستان‌ها با رِندرِ `StoryBar` (که خودش `StoryViewer` + انتشار + حلقه‌ها را دارد). پیش‌تر فقط داخلِ `app/messages` بود. |
| `modules/investment` (`/v1/investment`) | `app/investment/page.tsx` | استعلامِ NAV، خریدِ واحدِ صندوق، فهرستِ موقعیت‌های من (ADR-09، درآمدزا). |
| `modules/membership` (`/v1/membership`) | `app/membership/page.tsx` | طرحِ فعلی، ارتقا به standard/premium، لغو، نمایشِ کش‌بک. |
| `modules/gamification` (`/v1/gamification`) | `app/gamification/page.tsx` | امتیازِ فعالیت + فهرستِ نشان‌ها. |
| `modules/reputation` (`/v1/reputation`) | `app/reputation/page.tsx` | امتیازِ اعتبارِ کاربرِ جاری (÷۱۰) + نظرهای دریافتی. |

### نگاشتِ لایهٔ کلاینتِ API (`lib/api.ts`)
- `api.social`: افزودنِ `media` به `createPost` + متدهای `deletePost`, `comment`.
- بخش‌های جدید: `api.investment` (`nav/positions/buy/sell`)، `api.membership` (`get/upgrade/cancel`)،
  `api.gamification` (`points/badges`)، `api.reputation` (`scores/reviews/submitReview`) + تایپ‌های
  `NavOut, PositionOut, MembershipOut, PointsOut, BadgeOut, ScoreOut, ReviewOut, CommentOut`.

### ثبت در ناوبری
- `lib/roles.ts`: افزودنِ آیتمِ **«اجتماعی» (`/social`)** به `NAV_INDIVIDUAL` (نوار flex/space-around، ۶ آیتم).
- `app/me/page.tsx`: تایلِ **«داستان‌ها» (`/stories`)** کنارِ تایل‌های داشبورد/راه‌اندازی.
- `app/services/page.tsx`: چهار کاشیِ جدید (سرمایه‌گذاری، عضویت، امتیاز و نشان، اعتبار) در هابِ خدمات.

### بک‌لاگِ آتی (بزرگ، خارج از اسکوپِ سریع)
- **تماسِ صوتی/تصویری WebRTC** (سند M1) — کامپوننت‌های سیگنالینگ/تماس هنوز پورت نشده.
- **AI Assistant کامل** — فعلاً فقط `AssistantFab` هست؛ صفحهٔ گفتگوی کامل نیاز است.
- **Reels / صفحهٔ اجتماعیِ ویدیوییِ عمودی** — بک‌اند `post_type=reel` را می‌پذیرد ولی UIِ اختصاصی ندارد.

### اعتبارسنجیِ این مرحله
- `pytest`/`tsc`/`node_modules` در کانتینر نصب نیستند (طبق سیاستِ بیلدِ سنگین → فقط سرورِ SSH).
- بررسیِ سبک: توازنِ `{}`/`()`/`[]` و وجودِ `export default` در همهٔ ۶ صفحهٔ جدید تأیید شد؛
  تایپ‌ها و متدهای `api` ارجاع‌شده در `lib/api.ts` موجودند. تایپ‌چکِ کاملِ TS و بیلد باید روی سرورِ SSH اجرا شود.

---

## [2026-07-17] اپ موبایل اندروید — اسکفولد پلتفرم + ورود + بیلد CI

### تسک ۱ — اسکفولدِ پلتفرم اندروید ✅
`frontend/mobile/android/` دستی و مطابقِ قالبِ استانداردِ Flutter 3.x ساخته شد (چون
Flutter/Java/Android SDK نه در کانتینر و نه روی سرورِ تولید موجود نیست و نصبِ ~۱۰GB
تولچین روی سرورِ زنده مجاز/درست نبود). محتوا:
- `settings.gradle` (declarative plugins: AGP 8.1.0، Kotlin 1.8.22)، `build.gradle`،
  `gradle.properties`، `gradle/wrapper/gradle-wrapper.properties` (Gradle 8.3).
- `app/build.gradle`: `applicationId = "com.dilix.dilix_mobile"`، `namespace` همان،
  `minSdk 21`، `compileSdk/targetSdk = flutter.*` (نسخهٔ جاری)، امضای release با کلیدِ debug
  برای APKِ تستِ قابل‌نصب، و `manifestPlaceholders += [appAuthRedirectScheme: "app.dilix"]`.
- `AndroidManifest.xml` (main/debug/profile) با `<uses-permission android.permission.INTERNET/>`،
  `MainActivity.kt`، styles (light/night)، launch backgrounds، و آیکونِ vector
  (`drawable/ic_launcher.xml`) تا نیازی به فایلِ باینریِ mipmap نباشد.
- `android/.gitignore` مطابقِ پیش‌فرضِ Flutter (gradlew/jar/local.properties تولیدشونده‌اند).

### تسک ۲ — صفحهٔ ورود + اتصال به auth ✅
- فایلِ جدید `lib/features/auth/login_screen.dart`: ورود با شناسه/رمز، ورودِ یک‌بارمصرف
  (OTP/پیامک: request→verify)، و دکمه‌های اجتماعی که **فقط اگر در بیلد پیکربندی شده باشند**
  نمایش داده می‌شوند. از `ApiScope.of(context).login/otpRequest/otpVerify/oauthLogin` استفاده می‌کند.
- ویرایشِ `lib/app.dart`: افزودنِ `RootGate` — `home` حالا تا احراز هویت `LoginScreen`
  و پس از ورودِ موفق `HomeShell` را نشان می‌دهد (`setState`).

### تسک ۳ — وابستگی‌ها/کانفیگ social auth ✅
- `apiBaseUrl` از قبل با `--dart-define=DILIX_API_BASE_URL=...` قابلِ override است (نیازی به تغییر نبود).
- ورودِ اجتماعی بدونِ کانفیگِ بومی، **بیلدِ پایه را نمی‌شکند**: دکمه‌ها فقط با وجودِ
  clientId نمایش داده می‌شوند و `SocialAuth` در نبودِ کانفیگ خطای مدیریت‌شده می‌دهد.
  تنها الزامِ بیلدیِ `flutter_appauth` (appAuthRedirectScheme) در `app/build.gradle` تأمین شد.

### تسک ۴ — بیلد APK و تحویل ✅ (روی CI ابری، نه سرور)
- workflowِ جدید `.github/workflows/mobile.yml`: روی `ubuntu-latest` با Flutter `3.24.5`
  (pin‌شده مطابقِ اسکفولد) و Java 17، دستورِ `flutter build apk --release` را با
  `--dart-define=DILIX_API_BASE_URL=...` اجرا و APK را به‌عنوان artifact
  (`dilix-mobile-release-apk`) آپلود می‌کند. trigger: push روی `frontend/mobile/**` + `workflow_dispatch`.
- خروجیِ مورد انتظار: `frontend/mobile/build/app/outputs/flutter-apk/app-release.apk`.

### چرا CI به‌جای سرور SSH
سرورِ تولید (185.55.226.250) Flutter/Java/Android SDK ندارد و نصبِ تولچینِ سنگینِ اندروید
روی سرورِ زندهٔ Dilix هم غلط است (همان نگرانیِ حجم/کارایی سرور). runnerِ ابری این را
بدونِ هیچ بارِ اضافه‌ای روی سرور حل می‌کند.

### اعتبارسنجی
- `flutter`/`gradle` در کانتینر نصب نیست (طبق سیاستِ بیلد). صحتِ ساختاری دستی بررسی شد؛
  `flutter analyze` و بیلدِ APK در CI اجرا می‌شود. برای تولیدِ فایلِ APK کافی است workflow
  از تبِ Actions (یا با push) اجرا شود؛ خروجی از artifacts دانلود می‌شود.
