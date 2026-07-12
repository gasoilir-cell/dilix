# STATUS — گزارش وضعیت مخزن Dilix

تاریخ: 2026-07-12 · نوع: تحلیل و گزارش (بدون حذف/جابجایی فایل)

---

## Task 1 — تست‌های Core (بلاک‌کننده)

**نتیجه: ✅ 98 passed / 0 failed**

- دستور: `cd backend/services/core && PYTHONPATH=. pytest -v`
- برای اجرا، DB تستی باید به aiosqlite اشاره کند (وابستگی dev):
  `DILIX_DATABASE_URL="sqlite+aiosqlite:///:memory:" PYTHONPATH=. pytest`
- ۹ فایل تست، ۹۸ کیس، همه سبز: unit, m3, m4, m5, payments, saman, carrier, insurance, auth_social.

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
| **wallet**| — | **غایب (هیچ صفحه‌ای نیست)** |
| provider  | `app/provider/page.tsx` (235 خط) | موجود — کامل‌ترین |
| services  | `app/services/page.tsx` (30) + marketplace/telecom (استاب) | استاب |
| login     | `app/login/page.tsx` (38) | موجود |
| legal     | `privacy` (30) / `terms` (24) | موجود |

نتیجه: اسکلتِ frontend/web پایه‌است؛ صفحاتِ اصلی به‌جز **wallet** حضور دارند ولی اغلب سبک‌اند.
نسخه‌ی غنی و کاملِ همان صفحات به‌صورت فایل‌های stray در روت مخزن پراکنده است (جدول Task 2).

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
- **اعتبارسنجی نهایی:** کلِ سوئیت بدونِ env دستی → **114 passed** (۹۸ قبلی + ۱۶ جدید).
- ⚠️ همچنان تستِ integration واقعی (DB + auth override) برای اندپوینت‌ها آتی است.
