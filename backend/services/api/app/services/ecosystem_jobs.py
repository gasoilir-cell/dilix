"""
Dilix — نگهداریِ دوره‌ایِ اکوسیستم (Mini Program + Ads) — فاز ۴

دو جاروبِ ارزان با یک حلقه:

- **انقضای درخواست‌های پرداختِ برنامه‌ها** — درستیِ کار به این حلقه بند نیست
  (`_effective_status` هر درخواستِ سررسیدشده را همان لحظه منقضی می‌شمارد)؛
  این فقط فهرستِ کاربر را تمیز نگه می‌دارد.
- **بستنِ کمپین‌های تمام‌شده** — این یکی *واقعاً* لازم است: بدونِ آن بودجهٔ
  کمپینی که بازهٔ زمانی‌اش تمام شده تا ابد در کیفِ تبلیغ‌دهنده بلوکه می‌ماند.

هر دو در یک task هستند چون هم‌کادنس‌اند و جدا کردنشان فقط تعدادِ تایمرهای
بیکار را زیاد می‌کرد. هر جاروب استثنای خودش را می‌بلعد تا شکستِ یکی دیگری را
از دور خارج نکند.
"""
import asyncio

import structlog

from app.core.database import AsyncSessionLocal

log = structlog.get_logger(__name__)


async def ecosystem_sweep_once() -> tuple[int, int]:
    from app.api.v1.ads.router import close_finished_campaigns
    from app.api.v1.miniapps.router import expire_stale_payments

    expired = 0
    closed = 0
    async with AsyncSessionLocal() as db:
        try:
            expired = await expire_stale_payments(db)
        except Exception as exc:
            await db.rollback()
            log.warning("miniapp_payment_expiry_error", error=str(exc))
        try:
            closed = await close_finished_campaigns(db)
        except Exception as exc:
            await db.rollback()
            log.warning("ads_close_error", error=str(exc))
    if expired or closed:
        log.info("ecosystem_sweep", payments_expired=expired, campaigns_closed=closed)
    return expired, closed


async def periodic_ecosystem_jobs(interval_seconds: int = 3600,
                                  initial_delay: int = 70) -> None:
    """حلقهٔ ساعتی؛ هرگز استثنا بیرون نمی‌دهد تا خطای یک دور سرویس را نخواباند."""
    try:
        await asyncio.sleep(initial_delay)
        while True:
            try:
                await ecosystem_sweep_once()
            except Exception as exc:
                log.warning("ecosystem_jobs_loop_error", error=str(exc))
            await asyncio.sleep(interval_seconds)
    except asyncio.CancelledError:
        pass
