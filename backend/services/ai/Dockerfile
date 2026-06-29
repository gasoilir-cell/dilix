# ── Dilix AI Service Dockerfile ──────────────────────────────────────────────
# Multi-stage build: builder → runtime
# بیلد سنگین روی سرور SSH انجام می‌شود (طبق سیاست پروژه).

# Stage 1: builder
FROM python:3.12-slim AS builder
WORKDIR /build

COPY . /build/ai

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
        fastapi "uvicorn[standard]" pydantic pydantic-settings httpx && \
    pip install --no-cache-dir -e /build/ai

# Stage 2: runtime
FROM python:3.12-slim AS runtime
WORKDIR /app

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . /app

RUN useradd -r -s /bin/false dilix && chown -R dilix:dilix /app
USER dilix

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001", \
     "--workers", "2", "--loop", "uvloop", "--log-level", "info"]
