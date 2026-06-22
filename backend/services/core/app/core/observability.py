"""راه‌اندازی OpenTelemetry — Traces + Metrics (سند ۰، M0).

بسته‌های مورد نیاز (اضافه به pyproject.toml در production):
  opentelemetry-sdk
  opentelemetry-instrumentation-fastapi
  opentelemetry-instrumentation-sqlalchemy
  opentelemetry-exporter-otlp-proto-grpc

با DILIX_OTEL_ENABLED=true فعال می‌شود.
در development به‌صورت پیش‌فرض غیرفعال است تا dependency اجباری نباشد.
"""
from __future__ import annotations

import logging

logger = logging.getLogger("dilix.observability")


def setup_telemetry(app, settings) -> None:
    """راه‌اندازی OpenTelemetry برای FastAPI.

    باید در app startup قبل از هر middleware دیگری فراخوانی شود.
    """
    if not settings.otel_enabled:
        logger.info("OpenTelemetry disabled (DILIX_OTEL_ENABLED=false)")
        return

    try:
        from opentelemetry import trace
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.sdk.resources import Resource, SERVICE_NAME
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

        # ── Resource ──
        resource = Resource.create({
            SERVICE_NAME: settings.otel_service_name,
            "service.version": "0.4.0",
            "deployment.environment": settings.environment,
            "service.region": settings.region,
        })

        # ── TracerProvider ──
        provider = TracerProvider(resource=resource)

        # ── Exporter (OTLP gRPC → Collector → Jaeger/Tempo) ──
        try:
            from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
            exporter = OTLPSpanExporter(endpoint=settings.otel_exporter_otlp_endpoint)
            provider.add_span_processor(BatchSpanProcessor(exporter))
            logger.info("OTLP exporter → %s", settings.otel_exporter_otlp_endpoint)
        except ImportError:
            # اگر exporter نصب نیست، فقط console
            from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
            provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
            logger.warning("OTLP exporter not available — using ConsoleSpanExporter")

        trace.set_tracer_provider(provider)

        # ── FastAPI auto-instrumentation ──
        FastAPIInstrumentor.instrument_app(
            app,
            tracer_provider=provider,
            excluded_urls="/health",
        )

        # ── SQLAlchemy auto-instrumentation ──
        SQLAlchemyInstrumentor().instrument(tracer_provider=provider)

        logger.info("OpenTelemetry initialized — service=%s", settings.otel_service_name)

    except ImportError as exc:
        logger.warning(
            "OpenTelemetry packages not installed (%s). "
            "Install: opentelemetry-sdk opentelemetry-instrumentation-fastapi",
            exc,
        )


def get_tracer(name: str = "dilix.core"):
    """دریافت tracer برای span دستی."""
    try:
        from opentelemetry import trace
        return trace.get_tracer(name)
    except ImportError:
        return _NoopTracer()


class _NoopTracer:
    """Tracer بی‌عملکرد برای زمانی که OTEL نصب نیست."""
    def start_as_current_span(self, name: str, **_):
        from contextlib import contextmanager
        @contextmanager
        def _noop():
            yield None
        return _noop()
