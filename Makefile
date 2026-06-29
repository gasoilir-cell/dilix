.PHONY: help infra-up infra-down core-install core-run core-test core-migrate core-relay \
	ai-install ai-run ai-test web-install web-dev mobile-get

help:
	@echo "Dilix — دستورات توسعه"
	@echo "  make infra-up      راه‌اندازی Postgres/Redis/ES/MinIO/NATS (محلی)"
	@echo "  make infra-down    توقف زیرساخت"
	@echo "  make core-install  نصب وابستگی‌های سرویس Core"
	@echo "  make core-run      اجرای سرویس Core (uvicorn)"
	@echo "  make core-test     اجرای تست‌های سرویس Core"
	@echo "  make core-migrate  اجرای مهاجرت‌های دیتابیس"
	@echo "  make core-relay    اجرای workerِ Outbox Relay (outbox → NATS)"
	@echo "  make ai-install    نصب وابستگی‌های dilix-ai-service"
	@echo "  make ai-run        اجرای dilix-ai-service (پورت 8001)"
	@echo "  make ai-test       اجرای تست‌های ai-service"
	@echo "  make web-install   نصب وابستگی‌های وب (روی سرور SSH)"
	@echo "  make web-dev       اجرای وب در حالت توسعه (روی سرور SSH)"
	@echo "  make mobile-get    دریافت وابستگی‌های Flutter (روی سرور SSH)"
	@echo ""
	@echo "  نکته: بیلد ایمیج/Kubernetes و بیلدِ فرانت فقط روی سرور SSH انجام شود."

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

ai-install:
	cd backend/services/ai && pip install -e ".[dev]"

ai-run:
	cd backend/services/ai && uvicorn app.main:app --reload --port 8001

ai-test:
	cd backend/services/ai && PYTHONPATH=. pytest -v

web-install:
	cd frontend/web && npm install

web-dev:
	cd frontend/web && npm run dev

mobile-get:
	cd frontend/mobile && flutter pub get
