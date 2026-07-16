# Dilix — Dilix Platform

اکوسیستم دیجیتال جهانی: یک بستر واسط برای ارتباط، حمل‌ونقل، بیمه، مالی و هوش مصنوعی.
Dilix خودش ارائه‌دهنده‌ی مالی/بیمه نیست؛ **بستری است که ارائه‌دهندگان دارای مجوز** را به کاربران وصل می‌کند.

> 📐 معماری کامل در [`docs/`](./docs/00-overview.md) — قبل از توسعه حتماً مطالعه شود.

---

## ساختار Mono-Repo

```
dilix/
├── docs/                      اسناد معماری (فاز ۱ تا ۹)
├── backend/
│   ├── libs/
│   │   └── shared/            Shared Kernel — Earth ID، رویدادها، خطاها
│   └── services/
│       ├── core/             Modular Monolith: لایه‌های ۰ تا ۳ (Identity, Auth, Social, Freight, …)
│       └── ai/               سرویس AI (LangGraph Supervisor + Agents)
├── frontend/
│   └── web/                   Super-App Shell (Next.js, PWA, RTL): فید، کره، پیام‌ها، خدمات، من
├── infra/
│   └── docker-compose.yml     زیرساخت توسعه‌ی محلی
└── Makefile
```

سرویس‌های بعدی (Engagement، Verticals، AI Gateway، Realtime Gateway) طبق
[سند ۴](./docs/04-microservice-design.md) به همین ساختار اضافه می‌شوند.

---

## وضعیت فعلی — Milestone 0–3 Backend + Web Shell

| مؤلفه | وضعیت |
|---|---|
| Shared Kernel (Earth ID, Events, Errors) | ✅ |
| سرویس Core — Modular Monolith | ✅ لایه‌های ۰ تا ۳ |
| Identity (Earth ID + Profile + Visibility opt-in) | ✅ |
| Auth (Register + Login + JWT، MFA/E2EE keys) | ✅ |
| Authorization (RBAC + ABAC سبک) | ✅ |
| Provider (ثبت‌نام + KYB + ثبت API) | ✅ |
| Engagement (Messaging/Social/Notifications/Stickers/Stories) | ✅ |
| Verticals (Payments/Escrow, Insurance, Carrier, Freight) | ✅ |
| Growth (Referral/Gamification/Membership/Telecom/Investment/Marketplace) | ✅ |
| تست‌ها | ✅ آخرین اجرای کامل ثبت‌شده: ۱۴۳ تست |
| Alembic migrations | ✅ baseline + migration رسمی stickers/stories |
| Web Super-App Shell | ✅ Next.js + RTL؛ wallet/notifications/support و صفحات خدمات |

---

## شروع سریع (توسعه‌ی محلی)

```bash
make infra-up          # Postgres/Redis/ES/MinIO/NATS
make core-install      # نصب وابستگی‌ها
cp backend/services/core/.env.example backend/services/core/.env
make core-migrate      # ساخت جداول
make core-run          # http://localhost:8000/docs
make core-test         # اجرای تست‌ها
# یا اجرای مستقیم روی SQLite درون‌حافظه‌ای:
# cd backend/services/core && DILIX_DATABASE_URL="sqlite+aiosqlite:///:memory:" PYTHONPATH=. pytest
```

وب (Super-App Shell):

```bash
cd frontend/web
cp .env.example .env.local      # NEXT_PUBLIC_API_BASE_URL → سرویس Core
npm install                     # روی سرور SSH / CI (نه در کانتینر سبک)
npm run dev                     # http://localhost:3000
```

> ⚠️ **سیاست بیلد:** بیلد ایمیج Docker، Kubernetes و بیلدهای سنگین فقط روی **سرور SSH** انجام می‌شوند، نه در محیط توسعه.

---

## اصول کلیدی

- **Database-per-Context** — هیچ JOIN بین Boundedها.
- **Event-Driven** — ارتباط بین‌Context از طریق رویداد (Outbox → NATS/Kafka).
- **Zero Trust + E2EE** — هیچ secret در کد؛ پیام‌ها فقط روی دستگاه رمزگشایی می‌شوند.
- **Privacy by design** — نقشه‌ی افراد opt-in و با fuzzing موقعیت.
