# ── Dilix Core Service Dockerfile ────────────────────────────────────────────
# Multi-stage build: builder → runtime
# بیلد سنگین روی سرور SSH انجام می‌شود (طبق سیاست پروژه).

# Stage 1: builder
FROM python:3.12-slim AS builder
WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev && rm -rf /var/lib/apt/lists/*

COPY ../../libs/shared /build/shared
COPY . /build/core

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e /build/shared && \
    pip install --no-cache-dir \
        fastapi "uvicorn[standard]" pydantic pydantic-settings \
        "sqlalchemy[asyncio]" asyncpg alembic \
        pyjwt "passlib[argon2]" email-validator \
        nats-py httpx pyotp qrcode \
        opentelemetry-sdk \
        opentelemetry-instrumentation-fastapi \
        opentelemetry-instrumentation-sqlalchemy \
        opentelemetry-exporter-otlp-proto-grpc && \
    pip install --no-cache-dir -e /build/core

# Stage 2: runtime
FROM python:3.12-slim AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . /app

RUN useradd -r -s /bin/false dilix && chown -R dilix:dilix /app
USER dilix

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--workers", "2", "--loop", "uvloop", "--log-level", "info"]
