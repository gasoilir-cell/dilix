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

---

## [2026-07-18] بیلدِ اولین APK واقعی — موفق ✅

ریپازیتوریِ گیت‌هاب (`gasoilir-cell/dilix`) به‌عنوان remote ست شد، کدِ موبایل push شد و
workflowِ `mobile.yml` چند دور با شکست‌های واقعی (نه فرضی) اجرا و روتِ هرکدام رفع شد:

1. **`CardThemeData` نبود** → Flutter pin‌شده (۳.۲۴.۵) خیلی قدیمی بود؛ pin حذف و
   `channel: stable` گذاشته شد (روی runner به Flutter 3.44.6 resolve شد).
2. **تضادِ نسخهٔ `intl`** → SDKِ `flutter_localizations` نیازِ `intl 0.20.2` دارد؛
   pubspec به `intl: ^0.20.2` بروزرسانی شد.
3. **تضادِ Groovy/Kotlin DSL در `android/`** → تمپلیتِ جدیدِ Flutter از `build.gradle.kts`
   استفاده می‌کند و اسکفولدِ دستیِ Groovیِ قدیمی با آن هم‌زیستی نمی‌کرد. راه‌حل: CI حالا
   هر بار `rm -rf android && flutter create --platforms=android ...` را تازه اجرا می‌کند
   (نه `--overwrite`) و سپس customization patch (minSdk/compileSdk/manifestPlaceholders/
   INTERNET permission) را روی فایل‌های `.kts` اعمال می‌کند.
4. **`checkReleaseAarMetadata` fail (flutter_appauth/flutter_facebook_auth/flutter_secure_storage)**
   → `flutter.compileSdkVersion` روی این کانالِ Flutter به ۳۱ resolve می‌شد درحالی‌که
   وابستگی‌های transitive این پلاگین‌ها حداقل compileSdk=۳۶ می‌خواهند. چون هرکدام
   ماژولِ Gradleِ جداگانه‌اند (نه فقط `:app`)، یک `subprojects { afterEvaluate {...} }` در
   ریشهٔ `android/build.gradle.kts` اضافه شد تا compileSdk را روی همهٔ ماژول‌های
   `com.android.library` (به‌جز `:app` که خودش مستقیم ست می‌شود) به ۳۶ force کند.

### نتیجه
- **بیلد موفق**: workflow run [`0c8a043`](https://github.com/gasoilir-cell/dilix/actions/runs/29631673107) → `Build Release APK` سبز.
- **APK تحویل داده شد**: `outputs/app-release.apk` (~۵۰ مگابایت، امضاشده با کلیدِ debug
  برای نصبِ تستی؛ برای انتشار در Play Store باید با کلیدِ release واقعی امضا شود).
- ورودِ اجتماعی (Google/Microsoft/Apple/Facebook) در این APK کامپایل می‌شود اما تا وقتی
  client-idهای واقعی در بیلد ست نشوند دکمه‌هایش مخفی می‌مانند؛ ورود با
  رمز/OTP کاملاً فعال است.

---

## [2026-07-18] هم‌ترازیِ اپ موبایل با web — ماندگاریِ ورود + کیفِ پاداش/اعلان‌ها

- **ماندگاریِ نشست**: توکن‌ها با `shared_preferences` ذخیره و هنگامِ باز شدنِ اپ
  بازخوانی می‌شوند (`ApiClient.loadSession/_persistTokens/logout`). `RootGate`
  اکنون پیش از انتخابِ ورود/خانه، `loadSession()` را async اجرا و تا پایان یک
  اسپینر نشان می‌دهد → کاربر با هر بار باز کردنِ اپ مجبور به ورودِ دوباره نیست.
- **صفحهٔ «حساب من»** تکمیل شد: کارتِ کیفِ پاداش (امتیاز از `/v1/gamification/points`)،
  بخشِ اعلان‌ها (از `/v1/notifications` با شمارشِ نخوانده‌ها و علامت‌گذاریِ خوانده‌شده
  روی `/v1/notifications/{id}/read`)، لینکِ پشتیبانی (ارجاع به دستیارِ هوشمند) و
  دکمهٔ خروج از حساب.
- مدلِ `NotificationItem` و متدهای کلاینت (`notifications`, `markNotificationRead`,
  `rewardPoints`) افزوده شد. همهٔ endpointها با روترهای واقعی Core تطبیق داده شدند.
- **اعتبارسنجی**: Flutter در کانتینر نصب نیست (طبق سیاستِ بیلد سنگین)، پس به‌جای
  `flutter analyze` موازنهٔ پرانتز/براکت و صحتِ import/type دستی بررسی شد (سبز).
- **تصمیم‌های آگاهانه (بدون گسترشِ scope):** ساختارِ موجودِ `lib/features/*` +
  مسیریابیِ `Navigator` حفظ شد و به go_router/`lib/screens` مهاجرت داده نشد تا کارِ
  کاملِ قبلی دوباره‌کاری/تخریب نشود. داده‌ی واقعیِ صفحهٔ پیام‌ها موکول ماند چون
  Core هنوز endpointِ list-rooms ندارد (نیازمندِ کارِ backend، خارج از این scope).

### پیام‌های اپ موبایل — دادهٔ واقعی (نه placeholder)
- `features/messages/messages_screen.dart` بازنویسی شد: بازکردنِ گفتگویِ مستقیم با
  Earth ID طرفِ مقابل + `ChatView` با لیستِ پیام (پولِ ۵ثانیه‌ای) و ارسال، روی
  endpointهایِ واقعیِ `/v1/messaging/rooms`, `.../{id}/messages`.
- `api_client.dart`: متدهای `createDirectRoom`/`roomMessages`/`sendMessage`.
- `models.dart`: مدل‌های `ChatRoom` و `ChatMessage` (منطبق با `RoomOut`/`MessageOut` Core).
- محدودیت: Core endpointِ فهرستِ اتاق‌ها ندارد → لیستِ گفتگوهای گذشته نمایش داده
  نمی‌شود (گفتگو با Earth ID باز می‌شود). این نیازمندِ کارِ backend است.

### endpointِ فهرستِ اتاق‌ها (list-rooms) — رفعِ گپِ ثبت‌شده
- **backend** `messaging/router.py` + `service.py`: افزودنِ `GET /v1/messaging/rooms`
  (`service.list_rooms`) که اتاق‌های عضوِ کاربرِ فعلی را برمی‌گرداند، مرتب بر اساسِ
  جدیدترین فعالیت (آخرین پیام؛ در نبودِ پیام، `created_at` اتاق) با subqueryِ
  `max(sent_at)` + `coalesce`.
- **موبایل** `api_client.listRooms()` + `messages_screen`: فهرستِ گفتگوها بالای
  فرمِ «گفتگویِ جدید» (tap→`ChatView`، رفرش پس از بازگشت).
- **web** `lib/api.ts messaging.listRooms` + `app/messages/page.tsx`: نمایشِ لیست
  اتاق‌ها (پولِ ۱۰ثانیه‌ای، دکمهٔ بازگشت به فهرست از داخلِ اتاق).
- **تست** `tests/test_messaging_integration.py`: (۱) فهرست فقط اتاق‌های خودِ کاربر
  را می‌دهد نه کاربرِ دیگر؛ (۲) اتاقِ دارای پیامِ جدیدتر بالای فهرست می‌آید.
- اعتبارسنجی: `py_compile` سبز، موازنهٔ پرانتزِ فرانت سبز. اجرای `pytest`/`flutter`
  در کانتینر ممکن نیست (deps نصب نیست، طبق سیاستِ بیلد) → روی سرور SSH اجرا شود.

### دستیارِ هوشمندِ موبایل — صفحهٔ گفتگوی کامل (۲۰۲۶-۰۷-۱۸)
- **باگِ رفع‌شده:** `aiInvoke` قدیمی مسیرِ ناموجودِ `/v1/ai/conversations/{id}/messages`
  و یک شناسهٔ جعلیِ timestamp را صدا می‌زد → عملاً کار نمی‌کرد (۴۰۴/۴۰۴).
- **موبایل** `api_client.dart`: متدهای واقعیِ AI روی `/v1/ai` →
  `createAiConversation(agentType)`, `aiConversations()`, `aiHistory(id)`, `aiChat(id,msg)`.
  مدل‌های `AiConversation`/`AiMessage` در `models.dart`.
- **UI** `features/assistant/assistant_sheet.dart`: چتِ پایدارِ واقعی؛ انتخاب‌گرِ تخصص
  (۷ agent: personal/freight/insurance/financial/matchmaking/travel/business)، ساختِ
  مکالمهٔ واقعی، حبابِ کاربر/دستیار، auto-scroll، نوارِ خطا. هم‌تراز `AssistantPanel` وب.
- بک‌اند `modules/ai` و web `AssistantPanel` از قبل کامل بودند؛ فقط گپِ موبایل بسته شد.
- اعتبارسنجی: موازنهٔ براکت/پرانتز سبز، بدونِ ارجاعِ باقی‌مانده به `aiInvoke`.
  اجرای `flutter analyze`/`flutter run` روی سرور SSH (طبق سیاستِ بیلد).

## دستیارِ هوشمندِ موبایل — صفحهٔ گفتگوی کامل (feat/mobile-assistant)
- **باگِ رفع‌شده:** `aiInvoke` قدیمی مسیرِ ناموجودِ `/v1/ai/conversations/{id}/messages`
  و یک `conversationId` جعلی (timestamp) را صدا می‌زد → عملاً کار نمی‌کرد.
- **موبایل** `api_client.dart`: متدهای واقعیِ AI روی Core →
  `createAiConversation` (`POST /v1/ai/conversations`)، `aiConversations`
  (`GET /v1/ai/conversations`)، `aiHistory` (`GET .../history`)، `aiChat`
  (`POST .../chat`). مدل‌های `AiConversation`/`AiMessage` در `models.dart`.
- **UI** `features/assistant/assistant_sheet.dart`: چتِ پایدار روی مکالمهٔ واقعی،
  دراپ‌داونِ انتخابِ agent (۷ تخصص مطابقِ pattern بک‌اند)، تغییرِ agent →
  مکالمهٔ تازه؛ هم‌تراز با `AssistantPanel` وب.
- اعتبارسنجی: موازنهٔ ()/[]/{} روی هر سه فایل سبز؛ صفرْ ارجاعِ باقی‌مانده به
  `aiInvoke`. اجرای `flutter analyze` در کانتینر ممکن نیست → روی سرور SSH.

---

## [2026-07-18] Reels — وب / موبایل / تست

**بک‌اند (Core):** `modules/social` فیلترِ نوعِ پست را روی فید دارد.
- `service.feed(..., post_type=None)`: اگر داده شود، فقط همان نوع (`.where(SocialPost.post_type == post_type)`).
- `router.feed`: کوئریِ اختیاریِ `post_type` (مثلاً `?post_type=reel`).

**وب (`frontend/web`):**
- `lib/api.ts` → `api.social.feed(limit, postType?)` که `post_type` را به کوئری map می‌کند.
- `app/reels/page.tsx`: فیدِ ویدیوییِ عمودیِ تمام‌صفحه با scroll-snap؛ پخش/مکث با
  `IntersectionObserver` (auto-play هنگام ورود به دید)، لایک و نظر مطابقِ قراردادهای
  `app/social/page.tsx`. استایل‌ها در `app/globals.css` (کلاس‌های `.reels*`/`.reel*`).
- ورودی‌ها: کاشیِ «ریلز» در `app/services/page.tsx` (مسیر `/reels`).

**موبایل (`frontend/mobile`):**
- `pubspec.yaml`: `video_player: ^2.9.2` (و `flutter_webrtc: ^0.12.3`).
- `core/api_client.dart`: `reelsFeed()` (`GET /v1/social/feed?post_type=reel`)،
  به‌علاوهٔ `feed(postType:)`, `reactToPost`, `commentOnPost`.
- `models.dart`: افزودنِ `media` به `Post` + getter `videoUrl` (کلیدِ url/media_url).
- `features/reels/reels_screen.dart`: `PageView` عمودی + `video_player`؛ تنها صفحهٔ
  فعال پخش می‌شود، tap برای پخش/مکث، لایک و شیتِ نظر. ورودی از کاشیِ «ریلز» در
  `features/services/services_screen.dart`.

**تست:** `tests/test_social_reels_integration.py` (۲ تست، الگوی messaging؛ ATTACHِ
schemaهای `social`+`events`). سناریو: A فالوِ B → B پست‌های reel/text/video می‌سازد →
`feed?post_type=reel` فقط ریل‌ها، فیدِ بدونِ فیلتر همه؛ و حالتِ خالی.

**اعتبارسنجی:** تستِ ریلز **۲ passed** (pytest در کانتینر با نصبِ dev-deps)؛
`py_compile` روی social service/router/test سبز؛ موازنهٔ ()/[]/{} روی همهٔ فایل‌های
وب و دارت سبز. اجرای `tsc`/`flutter analyze`/بیلد به سرور SSH/CI سپرده شد (سیاستِ بیلد).

---

## [2026-07-18] Marketplace — چرخهٔ کاملِ سفارش (وب/موبایل/بک‌اند/تست)

بازارگاه از «فقط آگهی» به جریانِ end-to-endِ سفارش کامل شد (place → accept → deliver → complete با escrow).

**بک‌اند (Core):**
- `marketplace/service.py` → `list_orders(db, earth_id)`: سفارش‌هایی که کاربر خریدار یا فروشندهٔ آن‌هاست (`or_`، جدیدترین اول).
- `marketplace/router.py` → `GET /v1/marketplace/orders` (`list[OrderOut]`، همان الگوی `get_current_earth_id`).

**وب (`frontend/web`):**
- `lib/api.ts`: تایپِ `OrderOut` + متدهای `placeOrder`, `listOrders`, `acceptOrder`, `deliverOrder`, `completeOrder` در `api.marketplace`.
- `app/services/marketplace/page.tsx`: دو تب «خدمات» / «سفارش‌های من»؛ دکمهٔ «سفارش» روی هر آگهی؛ اکشن‌های accept/deliver/complete بسته به نقش (خریدار/فروشنده) و وضعیت. فقط کلاس‌های CSS موجود (`card`/`btn`/`badge`/`row-between`).

**موبایل (`frontend/mobile`):**
- `core/api_client.dart`: `marketplaceListings({keyword})`, `createListing(...)`, `placeOrder(...)`, `marketplaceOrders()`, `orderAction(id, action)`.
- `models/models.dart`: مدل‌های `Listing` و `MarketOrder` (منطبق با `ListingOut`/`OrderOut`).
- `features/marketplace/marketplace_screen.dart` (جدید): `TabBar` خدمات/سفارش‌ها، جستجو، سفارش، و اکشن‌های چرخهٔ سفارش با تشخیصِ نقش از `me().earthId`. ورودی از کاشیِ «بازارگاه» در `features/services/services_screen.dart`.

**تست:** `tests/test_marketplace_integration.py` — تستِ `test_full_order_flow_and_my_orders_scope` افزوده شد (fixtureِ `mk_order_client` با ATTACHِ `marketplace`+`payments`+`events`). سناریو: A آگهی → B سفارش → A accept/deliver → B complete → و scopeِ `GET /orders` برای هر کاربر فقط سفارش‌های خودش (کاربرِ بی‌ربط: خالی).

**اعتبارسنجی:** `pytest tests/test_marketplace_integration.py` → **۳ passed**؛ `py_compile` روی service/router/test سبز؛ موازنهٔ ()/[]/{} روی همهٔ فایل‌های وب و دارت سبز. اجرای `tsc`/`flutter analyze`/بیلد به SSH/CI سپرده شد (سیاستِ بیلد).


## [2026-07-18] Stories — گپِ موبایل (نمایش‌گرِ داستان)

بک‌اند و وبِ داستان‌ها از قبل بودند؛ **گپِ موبایل** پر شد.

**موبایل (`frontend/mobile`):**
- `core/api_client.dart` بخشِ Stories: `storiesFeed()`, `userStories(earthId)`, `viewStory(storyId)`, `createStory(...)` روی `/v1/stories/...`.
- `models/models.dart`: مدل‌های `StoryRing` (منطبق با `RingOut`) و `Story` (منطبق با `StoryOut`).
- `features/stories/stories_screen.dart` (جدید): فیدِ حلقه‌ها (`StoriesScreen`) با `RefreshIndicator` و نشانگرِ دیده‌نشده؛ نمایش‌گرِ `StoryViewer` با `PageView`، نوارِ پیشرفت، caption و ثبتِ خودکارِ بازدید (`viewStory`، بدونِ شمارشِ بازدیدِ خودِ نویسنده). ورودی از کاشیِ «داستان‌ها» در `features/services/services_screen.dart`.

**اعتبارسنجی:** موازنهٔ ()/[]/{}/[] روی فایل‌های دارتِ تغییرکرده سبز. تغییرِ بک‌اند نداشت (py_compile لازم نبود). اجرای `flutter analyze`/بیلد به SSH/CI سپرده شد.


## [2026-07-18] WebRTC — تماسِ صوتی/تصویریِ موبایل (گپِ موبایل)

بک‌اندِ signaling (relayِ `call.offer/answer/end` + `ice.candidate` روی `WS /v1/ws`) و وبِ تماس از قبل بودند؛ **گپِ موبایل** پر شد.

**موبایل (`frontend/mobile`):**
- `core/api_client.dart`: accessorهای `accessToken` و `baseUrl` (برای اتصالِ WS).
- `features/call/call_service.dart` (جدید): `CallService extends ChangeNotifier` با `RTCPeerConnection` (STUN عمومیِ گوگل)، اتصالِ WS با `dart:io` (بدونِ وابستگیِ جدید)، پروتکلِ هم‌راستا با `CallManager.tsx` وب (`sdp {type,sdp}`، `candidate {candidate,sdpMid,sdpMLineIndex}`، همیشه `to`/`call_id`/`media`؛ سرور `from` می‌افزاید). مدیریتِ local/remote stream، صف‌کردنِ ICE پیش از remote-description، mute/toggle-camera/switch-camera، رد/قطع، و رفتارِ busy برای تماسِ هم‌زمان.
- `features/call/call_screen.dart` (جدید): `RTCVideoView` تمام‌صفحهٔ طرفِ مقابل + PiP محلی، دکمه‌های پاسخ/رد/قطع/میوت/دوربین، پشتیبانی صوتی و تصویری، و بستنِ خودکار با پایانِ تماس. تابعِ `startOutgoingCall(...)` سرویس را می‌سازد/وصل می‌کند و صفحه را باز می‌کند.
- `features/messages/messages_screen.dart`: دکمه‌های «تماسِ صوتی/تصویری» در AppBarِ `ChatView` (با تشخیصِ `peerEarthId` از پارامتر یا فرستندهٔ پیام).

**تست (`backend`):** `tests/test_realtime_webrtc.py` — دو کیسِ جدیدِ ردِ توکنِ WS (`test_ws_rejects_invalid_token` با کدِ 4001 و بدونِ `connect`، و `test_ws_rejects_non_access_token`) افزوده شد.

**اعتبارسنجی:** `pytest tests/test_realtime_webrtc.py` → **۴ passed**؛ `py_compile` سبز؛ موازنهٔ ()/[]/{} روی همهٔ فایل‌های دارتِ تازه/تغییرکرده سبز. اجرای `flutter analyze`/بیلد به SSH/CI سپرده شد (سیاستِ بیلد). امضایِ APK با کلیدِ release و client-idهای واقعیِ ورودِ اجتماعی نیازمندِ secret واقعی‌اند و به کاربر واگذار شدند.

## [2026-07-18] WebRTC — نصبِ سراسریِ سرویسِ تماس + overlayِ تماسِ ورودی (موبایل)

`CallService` منطقِ تماسِ ورودی را داشت اما هیچ‌جا سراسری ساخته/`init` نمی‌شد و overlayِ ورودی نداشت؛ این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `lib/app.dart`: `CallScope extends InheritedWidget` (مشابهِ `ApiScope`، `CallScope.of(context)`)؛ یک `CallService _call` واحد در `_DilixAppState` (در `dispose` آزاد می‌شود). پس از احرازِ هویت در `RootGate`، `CallScope.of(context).init()` (idempotent) صدا زده می‌شود تا WSِ signaling همیشه به تماسِ ورودی گوش دهد. **overlayِ سراسری** با `MaterialApp.builder` → `ListenableBuilder(listenable: _call)` که وقتی `phase != CallPhase.idle` صفحهٔ `CallScreen(service: _call)` را در `Stack`/`Positioned.fill` روی کلِ اپ نشان می‌دهد.
- `lib/features/call/call_screen.dart`: به `StatelessWidget`ِ مبتنی بر سرویسِ مشترک تبدیل شد (بدونِ `Navigator.pop`؛ نمایش/پنهان‌شدن با گیتِ سراسری). کنترل‌ها با `semanticLabel` برای تست.
- `lib/features/call/call_service.dart`: `init()` idempotent (گاردِ `_initialized` + try/catch دورِ initializeِ رندررها برای امنیت در محیطِ بی‌پلاگین) + seamِ `@visibleForTesting debugSetPhase(...)`.
- `messages_screen.dart` از همان نمونهٔ مشترک استفاده می‌کند (`startOutgoingCall`→`CallScope.of(context).startCall`).

**تست (`frontend/mobile`):** `test/call_flow_test.dart` (جدید، ۴ `testWidgets`) — با `debugSetPhase` فازِ سرویس را دستی می‌راند: idle→بدونِ overlay؛ incoming→نامِ طرف + دکمه‌های پاسخ/رد؛ tapِ رد→بازگشت به idle و محوِ overlay؛ active→«برقرار» + کنترل‌های فعال (WebRTCِ واقعی بای‌پس؛ کلاینتِ احرازنشده تا `init` سراغِ WS نرود؛ رسانهٔ audio تا `RTCVideoView` render نشود).

**اعتبارسنجی:** موازنهٔ ()/[]/{} روی `app.dart`/`call_screen.dart`/`call_service.dart`/`call_flow_test.dart` سبز. `flutter analyze`/`flutter test` در کانتینر اجراشدنی نیست (flutter نصب نیست) → به CI/SSH موکول شد.

## [2026-07-18] Parity موبایل — کیف پول + اعلان‌ها + اتصالِ تست به CI

وب صفحاتِ `wallet` و `notifications` داشت اما موبایل نداشت؛ این گپِ parity پر شد.

**CI (`.github/workflows/mobile.yml`):** پیش از بیلدِ APK یک stepِ `flutter test` افزوده شد تا `test/call_flow_test.dart` و `marketplace_screen_test.dart` روی همان runner اجرا شوند و شکستشان بیلد را متوقف کند (analyze از قبل non-blocking بود).

**موبایل (`frontend/mobile`):**
- `lib/features/wallet/wallet_screen.dart` (جدید): معادلِ `app/wallet/page.tsx` — کیفِ پاداش (موجودی به‌تفکیکِ ارز + شمارِ در انتظار)، سهم از درآمد، لینکِ دعوت، و پرداختِ امانی (bottom-sheetِ ساختِ escrow + تسویه/برگشتِ سفارش‌های همان نشست). کاشی‌های شارژ/برداشت به‌صورتِ غیرفعالِ توضیح‌دار.
- `lib/features/notifications/notifications_screen.dart` (جدید): معادلِ `app/notifications/page.tsx` — فهرست + علامت‌گذاریِ خوانده‌شده (تکی و «خواندنِ همه») با `RefreshIndicator`.
- `core/api_client.dart`: متدهای `rewardWallet()`/`revenueShare()` (growth) و `createEscrow()`/`capturePayment()`/`refundPayment()` (payments). `referralLink` اکنون `total_referred` را هم می‌خواند.
- `models/models.dart`: مدل‌های `RewardBalance`/`RewardWallet`/`RevenueShare`/`PaymentOrder` + فیلدِ `totalReferred` روی `ReferralLink`.
- اتصال به shell: کاشی‌های «کیف پول» و «اعلان‌ها» در `services_screen.dart`؛ کارت‌های `me_screen.dart` (کیفِ پول/اعلان‌ها) اکنون به صفحهٔ کامل navigate می‌کنند.

**اعتبارسنجی:** موازنهٔ ()/[]/{} روی همهٔ فایل‌های تازه/تغییرکرده سبز؛ سازگاریِ APIها با schemaهای بک‌اند (`RewardWalletOut`/`RevenueShareOut`/`PaymentOrderOut`) بررسی شد. `flutter analyze`/`flutter test` به CI/SSH موکول است (flutter در کانتینر نصب نیست). امضای APK release و client-idهای ورودِ اجتماعی دست‌نخورده و به کاربر واگذار شدند.

## [2026-07-18] Parity موبایل — سرمایه‌گذاری + عضویت/اعتبار + بیمه + ارتباطات

گپِ باقی‌ماندهٔ parity: ماژول‌هایی که وب صفحه داشت ولی موبایل نداشت (investment/membership/gamification/reputation)، و دو کاشیِ `null`ِ خدمات (بیمه/ارتباطات) که بک‌اندشان mount بود ولی UIِ موبایل نداشتند.

**موبایل (`frontend/mobile`):**
- `core/api_client.dart`: `investmentNav`/`investmentPositions`/`buyFund` (`/v1/investment`)؛ `membership`/`upgradeMembership`/`cancelMembership` (`/v1/membership`)؛ `gamificationBadges` (`/v1/gamification/badges`)؛ `reputationScores`/`reputationReviews` (`/v1/reputation`)؛ `createInsuranceQuote`/`issuePolicy` (`/v1/insurance`)؛ `telecomTopUp`/`activateEsim` (`/v1/telecom`).
- `models/models.dart`: `NavQuote`/`InvestmentPosition`/`Membership`/`Badge`/`ReputationScore`/`Review`/`InsurancePolicy`/`TopUp`/`Esim` (هم‌نگاشت با `NavOut`/`PositionOut`/`MembershipOut`/`BadgeOut`/`ScoreOut`/`ReviewOut`/`PolicyOut`/`TopUpOut`/`EsimOut`).
- `features/investment/investment_screen.dart` (جدید): استعلامِ NAV + خریدِ واحد (ورودی تومان → IRR ×۱۰) + فهرستِ موقعیت‌ها. معادلِ `app/investment/page.tsx`.
- `features/membership/membership_screen.dart` (جدید): پلنِ فعلی + ارتقا/لغو + بازگشتِ نقدی (`cashback_bps/100`) + نشان‌ها (gamification) + اعتبار (score/۱۰ و نظرها). معادلِ `app/membership`+`app/gamification`+`app/reputation`.
- `features/insurance/insurance_screen.dart` (جدید): استعلام (`quoted`) + صدور (`issue`) با نمایشِ حقِ بیمه/پوشش.
- `features/telecom/telecom_screen.dart` (جدید): دو تب — شارژ/اینترنت (`top-up`) و فعال‌سازیِ eSIM.
- `features/services/services_screen.dart`: کاشی‌های «سرمایه‌گذاری» و «عضویت» افزوده شد و کاشی‌های `null`ِ «بیمه»/«ارتباطات» به صفحه‌های واقعی وصل شدند.

**اعتبارسنجی:** موازنهٔ ()/[]/{} روی همهٔ فایل‌های تازه/تغییرکرده سبز؛ payloadها و پاسخ‌ها با schemaهای Core (`BuyRequest`/`UpgradeRequest`/`QuoteCreate`/`TopUpCreate`/`EsimCreate`) و path prefixها (`/v1/...`) تطبیق داده شدند. `flutter analyze`/`flutter test`/بیلد به CI/SSH موکول است (flutter در کانتینر نصب نیست). امضای release و client-idهای ورودِ اجتماعی دست‌نخورده ماندند.

## [2026-07-18] Parity موبایل — فیدِ اجتماعیِ تعاملی (پست/رسانه/لایک/نظر)

فیدِ موبایل (`features/feed/feed_screen.dart`) فقط-خواندنی بود (نمایشِ متن + شمارِ لایک/نظر، بدونِ کنش)؛ اما وب (`app/social/page.tsx`) فیدِ کاملِ تعاملی داشت. این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `core/api_client.dart`: متدِ `createPost({postType, content, media, visibility})` روی `POST /v1/social/posts` (منطبق با `PostCreate`). `reactToPost`/`commentOnPost`/`feed` از قبل بودند.
- `models/models.dart`: `Post.copyWithCommentCount(int)` برای افزایشِ خوش‌بینانهٔ شمارِ نظر پس از ثبت.
- `features/feed/feed_screen.dart` (بازنویسی): composer (متن + افزودنِ رسانه با URL از طریقِ `_MediaUrlSheet`، بدونِ نیاز به پلاگینِ انتخابِ فایل)، انتشار (`post_type` خودکار text/image/video)، لایک (`reactToPost`→به‌روزرسانیِ پست)، نظر (`commentOnPost`→افزایشِ شمار)، و نمایشِ رسانهٔ درون‌خطی (`Image.network` با `errorBuilder`؛ ویدیو با placeholderِ play). حالت‌ها با `_error`/`RefreshIndicator`.

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ `createPost` منطبق با `PostCreate` (فیلدهای post_type/content/media/visibility)؛ توکنِ رنگیِ `surfaceContainerHighest` هم‌راستا با سایرِ صفحه‌ها. عدمِ افزودنِ dependency جدید (بدونِ `image_picker`) تا اسکفولد/permissionهای اندروید در CI دست‌نخورده بماند. `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] Parity موبایل — کشفِ اطراف (Discovery)

وب `app/services/discovery/page.tsx` را داشت اما موبایل صفحهٔ discovery نداشت (هرچند `api_client.nearby`/`contactRequest` از قبل بودند). این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `models/models.dart`: `NearbyPerson` غنی شد با `ageRange` و `languages` (هم‌نگاشت با `age_range`/`languages` در schemaِ Core که فقط وقتی در `visible_fields` باشند پر می‌شوند).
- `features/discovery/discovery_screen.dart` (جدید): فیلترِ bbox (پیش‌فرضِ تهران `35.5,51.2,35.85,51.6`) + حرفه، فهرستِ افرادِ نزدیک (نام/نوع/حرفه/سن/زبان‌ها)، و دکمهٔ «درخواستِ ارتباط» (`contactRequest`، با علامت‌گذاریِ ارسال‌شده). معادلِ رفتارِ صفحهٔ وب.
- `features/services/services_screen.dart`: کاشیِ «کشفِ اطراف» افزوده شد.

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ مسیر `/v1/discovery/nearby?bbox=&profession=&limit=` و `/v1/discovery/{earthId}/contact-request` با روت‌های Core و فیلدهای پاسخِ `NearbyPerson` تطبیق داده شدند. `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] Parity موبایل — حمل‌ونقل تعاملی (اسنپِ بار / ثبتِ بار)

`FreightScreen` موبایل (در `features/services/services_screen.dart`) فقط-خواندنی بود (فهرستِ بار با وضعیتِ خام، بدونِ ثبت و بدونِ وزن)؛ اما وب (`app/services/freight/page.tsx`) فرمِ ثبتِ بار + برچسبِ فارسیِ وضعیت + نمایشِ وزن داشت. این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `core/api_client.dart`: متدِ `createCargo({title, origin, destination, weightGrams, budgetMinor?, currency})` روی `POST /v1/freight/cargo` (منطبق با `CargoPostCreate`).
- `models/models.dart`: `CargoPost` غنی شد با `weightGrams`/`budgetMinor`/`currency` (هم‌نگاشت با `weight_grams`/`budget_minor`/`currency` در `CargoPostOut`).
- `features/services/services_screen.dart` (`FreightScreen` بازنویسی): از `FutureBuilder` فقط-خواندنی به `StatefulWidget` تعاملی تبدیل شد؛ FAB برای باز/بستنِ فرمِ ثبتِ بار (عنوان/مبدأ/مقصد/وزنِ کیلوگرم → `weight_grams = kg×1000`)، درجِ خوش‌بینانه در بالای فهرست، `RefreshIndicator`، برچسبِ فارسیِ وضعیت (open→باز، matched→تطبیق‌یافته، in_transit→در مسیر، ...) هم‌راستا با `STATUS_LABEL` وب، و نمایشِ وزن به کیلوگرم.

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ `createCargo` منطبق با `CargoPostCreate` (title/origin/destination/weight_grams>0/currency). `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] Parity موبایل — صفحهٔ پشتیبانی (FAQ + راه‌های ارتباط)

وب `app/support/page.tsx` (پشتیبانی: راه‌های ارتباط + تماسِ مستقیم + FAQ) را داشت اما موبایل فقط یک SnackBarِ ارجاع به دستیار در me_screen داشت. این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `features/support/support_screen.dart` (جدید، بدونِ backend call): کارتِ «راه‌های ارتباط» (چیپِ «پشتیبانیِ آنلاین»→درون‌برنامه‌ای به `MessagesScreen`، ایمیل/تلفن)، کارتِ «تماسِ مستقیم» (متنِ قابلِ انتخاب/کپی)، و FAQِ آکاردئونی (`ExpansionTile`) با ۶ پرسشِ منطبق با وب، و فوترِ نسخه. بدونِ افزودنِ dependency جدید (بدونِ `url_launcher`) تا اسکفولد/permissionهای اندروید در CI دست‌نخورده بماند.
- `features/me/me_screen.dart`: کاشیِ «پشتیبانی» به‌جای SnackBar اکنون به `SupportScreen` می‌رود.

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ صفحه ایستا/بدونِ API است (parity محتوایی با وب). `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] Parity موبایل — داشبوردِ نقش‌محور (نمای کلی)

وب `app/dashboard/page.tsx` (لندینگِ نقش‌محور: سلام + هویت/نقش + کیفِ پول + پنل‌های میان‌برِ نقش + کره + همهٔ خدمات) را داشت اما موبایل معادل نداشت (تبِ خانه = فید، منطبق با `/` وب؛ اما `/dashboard` جداست). این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `features/dashboard/dashboard_screen.dart` (جدید): سلامِ زمان‌محور (`_greeting`، منطبق با تابعِ وب)، کارتِ هویت (نام + چیپِ نقش با `_roleLabels`=ROLE_LABELS + Earth ID ۱۲نویسه)، کاشیِ کیفِ پول (`rewardWallet`→balances، `amount_minor/100`+`pending_count`)، پنل‌های میان‌برِ مخصوصِ نقش (`_panelsByRole`=PANELS_BY_ROLE: راننده/صاحبِ بار→`FreightScreen`، فریلنسر→`ServicesScreen`) و میان‌برهای کره/همهٔ خدمات. بارگذاری با `me()`+`rewardWallet()`؛ `RefreshIndicator`.
- `features/me/me_screen.dart`: کاشیِ «نمای کلی» زیرِ کارتِ هویت افزوده شد که به `DashboardScreen` می‌رود (اتصال به ناوبریِ تبِ «من»).

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ از متدهای موجودِ `me()`/`rewardWallet()` استفاده می‌کند (بدونِ endpoint جدید). `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] Parity موبایل — پورتالِ ارائه‌دهنده (KYB/API/sandbox/webhook/کلید)

وب `app/provider/page.tsx` (پورتالِ خودسرویسِ ارائه‌دهنده: ثبت‌نامِ KYB، ثبتِ API، تستِ sandbox، webhook و صدورِ کلید) را داشت اما موبایل هیچ معادلی نداشت — بزرگ‌ترین گپِ باقی‌مانده. این گپ پر شد.

**موبایل (`frontend/mobile`):**
- `models/models.dart`: مدل‌های `Provider`/`ProviderApi`/`SandboxResult`/`Webhook`/`Credential` (هم‌نگاشت با `ProviderOut`/`ProviderApiOut`/`SandboxTestResult`/`WebhookOut`/`CredentialOut`؛ `secret`/`api_key` فقط هنگامِ ساخت).
- `core/api_client.dart`: ۶ متد روی `/v1/providers`: `registerProvider`→`POST /register`، `providerApis`→`GET /{id}/apis`، `registerProviderApi`→`POST /{id}/apis`، `providerSandboxTest`→`POST /{id}/apis/{apiId}/sandbox-test`، `registerProviderWebhook`→`POST /{id}/webhooks`، `issueProviderCredential`→`POST /{id}/credentials`.
- `features/provider/provider_screen.dart` (جدید): پیش از ثبت‌نام فرمِ KYB (نامِ حقوقی + `DropdownButtonFormField` نوعِ ارائه‌دهنده psp/insurer/carrier/telecom/third_party)؛ پس از آن هدرِ ارائه‌دهنده (KYB status)، ثبتِ API، فهرستِ APIها با «تستِ sandbox» (نمایشِ reachable/detail/latency)، ثبتِ webhook (نمایشِ secret فقط یک‌بار در `SelectableText`) و صدورِ کلیدِ sandbox/production (نمایشِ کلیدِ خام فقط یک‌بار). خطاها از `ApiException.detail`.
- `features/services/services_screen.dart`: کاشیِ «ارائه‌دهنده» (`Icons.hub_outlined`) افزوده شد.

**اعتبارسنجی:** موازنهٔ ()/[]/{} سبز؛ ۶ endpoint و payloadها با روتر/schemaهای Core (`/v1/providers`، `ProviderRegisterRequest`/`ProviderApiCreate`/`WebhookCreate`/`CredentialCreate`) تطبیق داده شدند. `flutter analyze/test/build` به CI موکول است.

## [2026-07-18] تستِ ویجتِ پورتالِ ارائه‌دهنده + بازبینیِ parity

**تست (`frontend/mobile/test/provider_screen_test.dart`):** طبقِ الگوی `marketplace_screen_test.dart` (`MockClient` + `ApiScope` + `_wrap` با locale فارسی). ۲ تست: (۱) رندرِ اولیهٔ فرمِ KYB — عنوانِ «پورتالِ ارائه‌دهنده»، فیلدِ «نامِ حقوقی»، مقدارِ پیش‌فرضِ «PSP (پرداخت)»، و با بازکردنِ دراپ‌داون گزینه‌های «بیمه‌گر»/«حمل‌کننده / راهداری»/«اپراتورِ ارتباطات»/«شخصِ ثالث»؛ (۲) وجودِ دکمهٔ «ثبت‌نام»، یک `TextField` و یک `DropdownButtonFormField`. رندرِ اولیه آفلاین است (بدونِ فراخوانیِ API).

**CI:** `mobile.yml` گامِ `flutter test` را دارد که همهٔ فایل‌های `test/` را glob می‌کند؛ تستِ جدید خودکار پوشش داده می‌شود (بدونِ نیاز به jobِ جدید).

**بازبینیِ parity (`app/provider/page.tsx` ↔ `provider_screen.dart`):** همهٔ اکشن‌ها و فیلدها منطبق‌اند — register(legal_name+provider_type ۵ نوع)، addApi(name+spec_url)، sandboxTest، addWebhook(url+event_types)، issueCredential(sandbox/production) و همهٔ نمایش‌ها (KYB status، env/status، reachable/detail/latency، secret/api_key یک‌بار). تنها تفاوتِ جزئی: وب پیش از ورود یک کارتِ راهنما نشان می‌دهد، موبایل خطای عدمِ‌ورود را پس از اکشن از `ApiException.detail` سطحی می‌کند — گپِ کاربردی نیست، بدونِ تغییرِ کد.

## [2026-07-18] Parity موبایل — دستاوردها + اعتبار + اسنادِ حقوقی (صفحاتِ مستقل)

سه صفحهٔ وب که مسیرِ مستقل داشتند اما در موبایل فقط به‌صورتِ ترکیبی در `MembershipScreen` بودند، اکنون به‌صورتِ صفحه‌های مستقل (parity با route وب) اضافه شدند. همهٔ API/مدل‌ها از قبل موجود بودند (بدونِ endpoint جدید).

**موبایل (`frontend/mobile`):**
- `features/gamification/gamification_screen.dart` (جدید): معادلِ `app/gamification`. AppBar «دستاوردها»؛ کارتِ «امتیازِ من» با چیپِ موجودی + `LinearProgressIndicator` (پیشرفت در پله‌ی ۱۰۰۰تایی، نمایشی/مشتق از موجودی) + «تا پله‌ی بعدی»؛ کارتِ «نشان‌ها» (`Wrap` از `Chip`). داده via `rewardPoints()` + `gamificationBadges()`.
- `features/reputation/reputation_screen.dart` (جدید): معادلِ `app/reputation`. AppBar «اعتبار»؛ کارتِ «امتیازِ اعتبار» (به‌تفکیکِ حوزه، `score/10` + شمارشِ نظر) و کارتِ «نظرهای دریافتی» (ستاره‌ها + حوزه + کامنت). داده via `me()` → `reputationScores/reputationReviews(earthId)`.
- `features/legal/legal_screen.dart` (جدید، StatelessWidget): معادلِ `app/legal/terms` + `app/legal/privacy`. دو `ExpansionTile` («قوانین و مقررات» ۲بند، «حریمِ خصوصی» ۳بند) با متنِ عیناً منطبق با صفحاتِ وب. صفحهٔ ایستا/بدونِ API.
- `features/services/services_screen.dart`: کاشی‌های «دستاوردها» (`Icons.emoji_events_outlined`) و «اعتبار» (`Icons.verified_outlined`) افزوده شد.
- `features/me/me_screen.dart`: کاشیِ «اسنادِ حقوقی» (`Icons.gavel_outlined`) → `LegalScreen`.

**تست (`frontend/mobile/test/gamification_screen_test.dart`):** الگوی `marketplace_screen_test.dart`؛ `MockClient` مسیرهای `points`/`badges` را با JSON حداقلی و بقیه را `[]` می‌دهد. ۲ تست: (۱) عنوانِ «دستاوردها» + «امتیازِ من» + «نشان‌ها» + چیپِ موجودی «1250» + `LinearProgressIndicator`؛ (۲) رندرِ نشانِ موکِ «اولین معامله».

**اعتبارسنجی:** موازنهٔ ()/[]/{} برای هر ۶ فایل سبز. `flutter analyze/test/build` به CI موکول (`mobile.yml` گامِ `flutter test` همهٔ `test/` را glob می‌کند). یادداشت: `MembershipScreen` همچنان نمایِ ترکیبیِ نشان/اعتبار را نگه داشته؛ صفحاتِ جدید مسیرِ مستقلِ parity با وب‌اند.

## [2026-07-18] تستِ ویجتِ notifications/membership/services + برچسبِ فارسیِ پلن

سه صفحهٔ فاقدِ تستِ ویجت (notifications, membership, services) پوشش داده شد و یک گپِ parity در نمایشِ پلنِ عضویت رفع شد.

**تست‌ها (`frontend/mobile/test`):**
- `notifications_screen_test.dart`: `MockClient` یک اعلانِ خوانده‌نشده می‌دهد و مسیرِ `/read` را ۲۰۴. ۲ تست: (۱) عنوانِ «اعلان‌ها» + عنوان/متنِ آیتم + چیپِ «جدید» + دکمهٔ «خواندنِ همه»؛ (۲) لمسِ اعلان → علامت‌گذاریِ خوانده‌شده و حذفِ چیپِ «جدید».
- `membership_screen_test.dart`: `MockClient` عضویتِ پلنِ `standard` می‌دهد. ۲ تست: (۱) «عضویت و اعتبار» + «عضویتِ فعلی» + «پلن‌ها» + برچسب‌های فارسیِ «رایگان»/«استاندارد»/«ویژه»؛ (۲) چیپِ «فعال» برای پلنِ جاری و دو دکمهٔ «انتخاب» برای بقیه.
- `services_screen_test.dart`: ۲ تست: (۱) هابِ «خدمات» با کاشی‌های «حمل‌ونقل»/«بیمه»/«دستاوردها»/«اعتبار»/«ارائه‌دهنده»؛ (۲) `FreightScreen` با موکِ باری در وضعیتِ `open` → نمایشِ برچسبِ فارسیِ «باز» (STATUS_LABEL).

**گپِ parity رفع‌شده (`membership_screen.dart`):** وب پلن‌ها را با برچسب/توضیحِ فارسی نشان می‌دهد (`PLANS`: رایگان/استاندارد/ویژه) اما موبایل کلیدِ خامِ `free/standard/premium` را نمایش می‌داد. `_planLabels`+`_planDescs` افزوده و `_plansCard` به برچسبِ فارسی + توضیح تغییر کرد.

**بررسیِ STATUS_LABEL وضعیت:** در وبِ `notifications` و `membership` وضعیت با برچسبِ فارسی نگاشت **نمی‌شود** (اعلان فقط چیپِ «جدید»؛ عضویت `status` خام) — موبایل هم مطابق است؛ نیازی به افزودنِ نگاشت نبود.

**اعتبارسنجی:** موازنهٔ ()/[]/{} برای هر ۴ فایل سبز. سه تستِ جدید توسط گامِ `flutter test` در CI پوشش داده می‌شوند.
