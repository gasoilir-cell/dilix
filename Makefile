.PHONY: help infra-up infra-down core-install core-run core-test core-migrate core-relay

help:
	@echo "Dilix — دستورات توسعه"
	@echo "  make infra-up      راه‌اندازی Postgres/Redis/ES/MinIO/NATS (محلی)"
	@echo "  make infra-down    توقف زیرساخت"
	@echo "  make core-install  نصب وابستگی‌های سرویس Core"
	@echo "  make core-run      اجرای سرویس Core (uvicorn)"
	@echo "  make core-test     اجرای تست‌های سرویس Core"
	@echo "  make core-migrate  اجرای مهاجرت‌های دیتابیس"
	@echo "  make core-relay    اجرای workerِ Outbox Relay (outbox → NATS)"
	@echo ""
	@echo "  نکته: بیلد ایمیج/Kubernetes فقط روی سرور SSH انجام شود."

infra-up:
	docker compose -f infra/docker-compose.yml up -d

infra-down:
	docker compose -f infra/docker-compose.yml down

core-install:
	cd backend/services/core && pip install -e ".[dev]" && pip install -e ../../libs/shared

core-run:
	cd backend/services/core && uvicorn app.main:app --reload

core-test:
	cd backend/services/core && PYTHONPATH=. pytest -v

core-migrate:
	cd backend/services/core && alembic upgrade head
