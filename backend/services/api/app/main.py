"""
Dilix API — نقطه ورود اصلی FastAPI
"""
import asyncio
import structlog
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.database import engine, Base
from app.core.redis import close_redis
from app.core.ratelimit import RateLimited, hit as ratelimit_hit, rate_limit_ip, rule_for_path
from app.api.v1.auth.router import router as auth_router
from app.api.v1.health.router import router as health_router
from app.api.v1.wallet.router import router as wallet_router
from app.api.v1.payment.router import router as payment_router
from app.api.v1.earth.router import router as earth_router

log = structlog.get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / Shutdown"""
    log.info("dilix_api_starting", version=settings.APP_VERSION, env=settings.ENV)

    # ایجاد جداول DB (در production از Alembic استفاده می‌شود)
    if settings.is_development:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        log.info("db_tables_created")

    # فیدِ زندهٔ نرخِ ارز: به‌روزرسانیِ دوره‌ایِ IRR در پس‌زمینه (بی‌خطر برای بوت).
    from app.services.fx_feed import periodic_fx_refresh
    app.state.fx_task = asyncio.create_task(periodic_fx_refresh())

    # تمدیدِ خودکارِ اشتراکِ سازندگان؛ بدونِ آن `auto_renew` فقط تیکی تزئینی است.
    from app.services.subscription_renew import periodic_subscription_renew
    app.state.subs_task = asyncio.create_task(periodic_subscription_renew())

    # آزادسازیِ خودکارِ وجهِ امانیِ سفارش‌های ارسال‌شده؛ بدونِ آن پولِ فروشنده
    # گروگانِ تأییدنکردنِ خریدار می‌ماند.
    from app.services.shop_autorelease import periodic_shop_autorelease
    app.state.shop_task = asyncio.create_task(periodic_shop_autorelease())

    # نگهداریِ اکوسیستم: انقضای پرداختِ برنامه‌ها و بستنِ کمپین‌های تمام‌شده؛
    # بدونِ دومی بودجهٔ کمپینِ سررسیدشده تا ابد بلوکه می‌ماند.
    from app.services.ecosystem_jobs import periodic_ecosystem_jobs
    app.state.eco_task = asyncio.create_task(periodic_ecosystem_jobs())

    log.info("dilix_api_ready")
    yield

    # Shutdown
    for name in ("fx_task", "subs_task", "shop_task", "eco_task"):
        task = getattr(app.state, name, None)
        if task is not None:
            task.cancel()
    await close_redis()
    await engine.dispose()
    log.info("dilix_api_shutdown")


app = FastAPI(
    title="Dilix API",
    description="Global B2B2C Orchestration Platform — پلتفرم اتصال جهانی",
    version=settings.APP_VERSION,
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
    lifespan=lifespan,
)

# ─── Middleware ──────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)


# ─── Request ID Middleware ────────────────────────────────────
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    import uuid
    request_id = str(uuid.uuid4())
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


# ─── Security Headers Middleware ─────────────────────────────
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """سرآیندهای امنیتی: کاهشِ سطحِ حمله (clickjacking/MIME-sniff/نشتِ referrer)."""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(self), microphone=(), camera=()"
    if settings.is_production:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


# ─── Rate Limit Middleware (auth) ─────────────────────────────
AUTH_PREFIX = "/api/v1/auth"


@app.middleware("http")
async def rate_limit_auth(request: Request, call_next):
    """سقفِ نرخ روی `/api/v1/auth/*` بر پایه‌ی IP.

    فقط متدهای تغییردهنده شمرده می‌شوند؛ خواندنِ پروفایل (GET /me) که اپ مرتب
    صدا می‌زند نباید به سقف بخورد.
    """
    if (
        request.url.path.startswith(AUTH_PREFIX)
        and request.method not in ("GET", "HEAD", "OPTIONS")
    ):
        try:
            await ratelimit_hit(
                f"ip:{request.url.path}",
                rate_limit_ip(request),
                rule_for_path(request.url.path),
            )
        except RateLimited as exc:
            # میان‌افزار بیرونِ محدوده‌ی exception handlerهاست، پس پاسخ را
            # مستقیم می‌سازیم — با همان قالبِ خطای بقیه‌ی API.
            return JSONResponse(
                status_code=429,
                headers={"Retry-After": str(exc.retry_after)},
                content={"detail": exc.as_detail()},
            )
    return await call_next(request)


# ─── Rate Limit Error Handler (route-level) ──────────────────
@app.exception_handler(RateLimited)
async def rate_limited_handler(request: Request, exc: RateLimited):
    return JSONResponse(
        status_code=429,
        headers={"Retry-After": str(exc.retry_after)},
        content={"detail": exc.as_detail()},
    )


# ─── Global Error Handler ─────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    log.error("unhandled_exception", error=str(exc), path=request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "خطای داخلی سرور. لطفاً دوباره تلاش کنید"},
    )


# ─── Routers ─────────────────────────────────────────────────
app.include_router(health_router, prefix="/api/v1")
app.include_router(auth_router, prefix="/api/v1")
app.include_router(wallet_router, prefix="/api/v1")
app.include_router(payment_router, prefix="/api/v1")
app.include_router(earth_router, prefix="/api/v1")


@app.get("/", tags=["Root"])
async def root():
    return {
        "name": "Dilix API",
        "version": settings.APP_VERSION,
        "status": "running",
        "docs": "/docs",
        "earth": "🌍",
    }

# ─── Static Files — آواتارهای کاربران ────────────────────────
from fastapi.staticfiles import StaticFiles
import os as _os
_os.makedirs('/var/www/dilix-api/uploads/avatars', exist_ok=True)
app.mount('/uploads', StaticFiles(directory='/var/www/dilix-api/uploads'), name='uploads')

# ─── Freight ─────────────────────────────────────────────────
from app.api.v1.freight.router import router as freight_router
app.include_router(freight_router, prefix="/api/v1")

# ─── Messages ─────────────────────────────────────────────────
from app.api.v1.messages.router import router as messages_router
app.include_router(messages_router, prefix="/api/v1")

# ─── Insurance ────────────────────────────────────────────────
from app.api.v1.insurance.router import router as insurance_router
app.include_router(insurance_router, prefix="/api/v1")

# ─── AI Chat ──────────────────────────────────────────────────
from app.api.v1.ai_chat.router import router as ai_chat_router
app.include_router(ai_chat_router, prefix="/api/v1")

from app.api.v1.referral.router import router as referral_router
app.include_router(referral_router, prefix="/api/v1")

# ─── Notifications ───────────────────────────────────────────
from app.api.v1.notifications.router import router as notifications_router
app.include_router(notifications_router, prefix="/api/v1")

# ─── Social Graph (Follow) ──────────────────
from app.models.social import Follow  # noqa: F401  (تا create_all جدول را بسازد)
from app.api.v1.social.router import router as social_router
app.include_router(social_router, prefix="/api/v1")

# ─── Calls (WebRTC signaling) ────────────────
from app.models.stickers import StickerPack, Sticker, StarredSticker, InstalledPack  # noqa: F401
from app.api.v1.stickers.router import router as stickers_router
app.include_router(stickers_router, prefix="/api/v1")
from app.models.stories import Story, StoryView  # noqa: F401
from app.api.v1.stories.router import router as stories_router
app.include_router(stories_router, prefix="/api/v1")
from app.api.v1.calls.router import router as calls_router
app.include_router(calls_router, prefix="/api/v1")

# ─── Reels (ویدیوهای کوتاه) ────────────────
from app.models.reels import Reel, ReelLike, ReelComment  # noqa: F401
from app.api.v1.reels.router import router as reels_router
app.include_router(reels_router, prefix="/api/v1")

# ─── Posts (فیدِ اجتماعی) ────────────────
from app.models.posts import Post, PostLike, PostComment, PostSave  # noqa: F401
from app.api.v1.posts.router import router as posts_router
app.include_router(posts_router, prefix="/api/v1")

# ─── Live (پخشِ زندهٔ ویدیویی ۱-به-چند) ────────────────
from app.models.live import LiveSession  # noqa: F401  (تا create_all جدول را بسازد)
from app.api.v1.live.router import router as live_router
app.include_router(live_router, prefix="/api/v1")

# ─── Provider Onboarding (خدمات‌دهندگان: بیمه/بانک/کارگزار) ────────────────
from app.api.v1.provider.router import router as provider_router
app.include_router(provider_router, prefix="/api/v1")

# ─── i18n / Globalization (زبان/ارز/تشخیصِ خودکار + ترجیحاتِ کاربر) ────────────────
from app.api.v1.i18n.router import router as i18n_router
app.include_router(i18n_router, prefix="/api/v1")

# ─── Paygate (رجیستریِ درگاه‌های پرداختِ pluggable + شارژِ کیف‌پول) ────────────────
from app.models.paygate import PaymentGateway, PaymentIntent  # noqa: F401  (تا create_all جدول‌ها را بسازد)
from app.api.v1.paygate.router import router as paygate_router
app.include_router(paygate_router, prefix="/api/v1")

# ─── FX (نرخِ ارز + تبدیلِ بین‌ارزی) ──────────────────────────────────────────────
from app.models.fx import FxRate  # noqa: F401  (تا create_all جدولِ fx_rates را بسازد)
from app.api.v1.fx.router import router as fx_router
app.include_router(fx_router, prefix="/api/v1")

# ─── Holdings (کیف‌پولِ چندارزی + تبدیلِ درون‌کیفی) ───────────────────────────────
from app.models.holdings import WalletHolding, HoldingTransaction  # noqa: F401  (تا create_all جدول‌ها را بسازد)
from app.api.v1.holdings.router import router as holdings_router
app.include_router(holdings_router, prefix="/api/v1")

# ─── MLM commission ledger (بازاریابیِ شبکه‌ایِ چندسطحی) ───────────────────────────
from app.models.mlm import MlmCommission  # noqa: F401  (تا create_all جدولِ mlm_commissions را بسازد)

# ─── Bills (قبوض و خدماتِ شهری) ──────────────────────────────────────────────
from app.api.v1.bills.router import router as bills_router
app.include_router(bills_router, prefix="/api/v1")

# ─── Business / Creator accounts + Insights + Subscriptions (فاز ۴) ──────────
from app.api.v1.business.router import router as business_router
from app.api.v1.business.subscriptions import router as subscriptions_router
app.include_router(business_router, prefix="/api/v1")
app.include_router(subscriptions_router, prefix="/api/v1")

# ─── Shop / Escrow checkout درون‌چت (فاز ۴) ──────────────────────────────────
from app.api.v1.shop.router import router as shop_router
app.include_router(shop_router, prefix="/api/v1")

# ─── Mini Program SDK (فاز ۴) ────────────────────────────────────────────────
from app.api.v1.miniapps.router import router as miniapps_router
app.include_router(miniapps_router, prefix="/api/v1")

# ─── Ads — تبلیغاتِ خودخدمت (فاز ۴) ───────────────────────────────────────────
from app.api.v1.ads.router import router as ads_router
app.include_router(ads_router, prefix="/api/v1")
