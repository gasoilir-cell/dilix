"""نقطه‌ی ورود سرویس Core — Dilix Modular Monolith (ADR-03).

همهٔ ماژول‌های دامنه در یک deployable با مرزهای ماژولارِ سفت قرار دارند.
در مراحلِ بعدی هر ماژول می‌تواند به microservice مستقل تبدیل شود.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from dilix_shared.errors import DilixError

from app.core.config import get_settings
from app.core.observability import setup_telemetry

# ── Layer 0 — پایه ──
from app.modules.auth.router import router as auth_router
from app.modules.identity.router import router as identity_router
from app.modules.provider.router import router as provider_router
from app.modules.kyc.router import router as kyc_router

# ── Layer 1 — Engagement Shell ──
from app.modules.messaging.router import router as messaging_router
from app.modules.social.router import router as social_router
from app.modules.stickers.router import router as stickers_router
from app.modules.stories.router import router as stories_router
from app.modules.notification.router import router as notification_router
from app.modules.earth.router import router as earth_router
from app.modules.discovery.router import router as discovery_router
from app.modules.ai.router import router as ai_router
from app.modules.realtime.router import router as realtime_router

# ── Layer 2 — Verticals درآمدی ──
from app.modules.payments.router import router as payments_router
from app.modules.insurance.router import router as insurance_router
from app.modules.carrier.router import router as carrier_router
from app.modules.freight.router import router as freight_router

# ── Layer 3 — رشد و توسعه ──
from app.modules.referral.router import router as referral_router
from app.modules.growth.router import router as growth_router
from app.modules.gamification.router import router as gamification_router
from app.modules.membership.router import router as membership_router
from app.modules.telecom.router import router as telecom_router
from app.modules.investment.router import router as investment_router
from app.modules.reputation.router import router as reputation_router
from app.modules.marketplace.router import router as marketplace_router

logging.basicConfig(level=logging.INFO)
settings = get_settings()

app = FastAPI(
    title="Dilix Core Service",
    version="0.4.0",
    description=(
        "Dilix Platform — Core Service (All Verticals). "
        "B2B2C Orchestration Platform — never holds funds, never issues policies."
    ),
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ── CORS ──
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if not settings.is_production else [
        "https://dilix.app",
        "https://app.dilix.app",
        "https://panel.dilix.app",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── OpenTelemetry ──
setup_telemetry(app, settings)


# ── Exception Handlers ──
@app.exception_handler(DilixError)
async def dilix_error_handler(request: Request, exc: DilixError) -> JSONResponse:
    """نگاشت خطاهای دامنه به RFC 7807 (سند ۵)."""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "type": f"https://dilix.app/errors/{exc.error_type}",
            "title": exc.error_type.replace("_", " ").title(),
            "status": exc.status_code,
            "detail": exc.detail,
            "instance": str(request.url.path),
        },
    )


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logging.getLogger("dilix.core").exception("Unhandled error: %s", exc)
    return JSONResponse(
        status_code=500,
        content={
            "type": "https://dilix.app/errors/internal_error",
            "title": "Internal Server Error",
            "status": 500,
            "detail": "خطای داخلی سرور — لطفاً دوباره تلاش کنید.",
            "instance": str(request.url.path),
        },
    )


# ── Health ──
@app.get("/health", tags=["system"])
async def health() -> dict:
    return {
        "status": "ok",
        "service": settings.service_name,
        "version": "0.4.0",
        "region": settings.region,
        "environment": settings.environment,
    }


@app.get("/health/ready", tags=["system"])
async def readiness() -> dict:
    """Kubernetes readiness probe."""
    from app.core.database import engine
    import sqlalchemy
    try:
        async with engine.connect() as conn:
            await conn.execute(sqlalchemy.text("SELECT 1"))
        return {"status": "ready"}
    except Exception as exc:
        return JSONResponse(status_code=503, content={"status": "not_ready", "detail": str(exc)})


# ── Routers ──

# Layer 0 — Platform Core
app.include_router(auth_router)
app.include_router(identity_router)
app.include_router(provider_router)
app.include_router(kyc_router)

# Layer 1 — Engagement Shell
app.include_router(messaging_router)
app.include_router(social_router)
app.include_router(stickers_router)
app.include_router(stories_router)
app.include_router(notification_router)
app.include_router(earth_router)
app.include_router(discovery_router)
app.include_router(ai_router)
app.include_router(realtime_router)

# Layer 2 — Verticals درآمدی
app.include_router(payments_router)
app.include_router(insurance_router)
app.include_router(carrier_router)
app.include_router(freight_router)

# Layer 3 — رشد، توسعه، بازارگاه
app.include_router(referral_router)
app.include_router(growth_router)
app.include_router(gamification_router)
app.include_router(membership_router)
app.include_router(telecom_router)
app.include_router(investment_router)
app.include_router(reputation_router)
app.include_router(marketplace_router)
