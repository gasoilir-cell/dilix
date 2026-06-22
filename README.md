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
│       └── core/              لایه ۰ (Modular Monolith): Identity · Auth · Authz · Provider
├── infra/
│   └── docker-compose.yml     زیرساخت توسعه‌ی محلی
└── Makefile
```

سرویس‌های بعدی (Engagement، Verticals، AI Gateway، Realtime Gateway) طبق
[سند ۴](./docs/04-microservice-design.md) به همین ساختار اضافه می‌شوند.

---

## وضعیت فعلی — Milestone 0 (Foundation)

| مؤلفه | وضعیت |
|---|---|
| Shared Kernel (Earth ID, Events, Errors) | ✅ |
| سرویس Core — اسکلت | ✅ |
| Identity (Earth ID + Profile + Visibility opt-in) | ✅ |
| Auth (Register + Login + JWT، اسکلت MFA) | ✅ |
| Authorization (RBAC + ABAC سبک) | ✅ |
| Provider (ثبت‌نام + KYB + ثبت API) | ✅ |
| تست‌های واحد | ✅ ۷ تست |
| Alembic migrations | ✅ پیکربندی |

---

## شروع سریع (توسعه‌ی محلی)

```bash
make infra-up          # Postgres/Redis/ES/MinIO/NATS
make core-install      # نصب وابستگی‌ها
cp backend/services/core/.env.example backend/services/core/.env
make core-migrate      # ساخت جداول
make core-run          # http://localhost:8000/docs
make core-test         # اجرای تست‌ها
```

> ⚠️ **سیاست بیلد:** بیلد ایمیج Docker، Kubernetes و بیلدهای سنگین فقط روی **سرور SSH** انجام می‌شوند، نه در محیط توسعه.

---

## اصول کلیدی

- **Database-per-Context** — هیچ JOIN بین Boundedها.
- **Event-Driven** — ارتباط بین‌Context از طریق رویداد (Outbox → NATS/Kafka).
- **Zero Trust + E2EE** — هیچ secret در کد؛ پیام‌ها فقط روی دستگاه رمزگشایی می‌شوند.
- **Privacy by design** — نقشه‌ی افراد opt-in و با fuzzing موقعیت.
