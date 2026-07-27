"""
Dilix — آزادسازیِ خودکارِ وجهِ سفارش‌های ارسال‌شده (فاز ۴)

بدونِ این حلقه، تنها راهِ رسیدنِ پول به فروشنده تأییدِ دستیِ خریدار بود؛ یعنی
هر خریدارِ بی‌تفاوت (یا بدنیت) می‌توانست وجهِ فروشنده را تا ابد بلوکه نگه دارد.

هر دور در تراکنشِ خودش تسویه می‌کند تا شکستِ یک سفارش بقیه را زمین نزند.
"""
import asyncio

import structlog

from app.core.database import AsyncSessionLocal

log = structlog.get_logger(__name__)


async def auto_release_once() -> int:
    """یک دورِ آزادسازی؛ تعدادِ سفارش‌های تسویه‌شده را برمی‌گرداند."""
    from app.api.v1.shop.router import auto_release_due

    async with AsyncSessionLocal() as db:
        done = await auto_release_due(db)
    if done:
        log.info("shop_orders_auto_released", count=done)
    return done


async def periodic_shop_autorelease(interval_seconds: int = 3600,
                                    initial_delay: int = 55) -> None:
    """حلقهٔ ساعتی؛ در lifespan به‌صورتِ task اجرا می‌شود و هرگز استثنا بیرون
    نمی‌دهد تا خطای یک دور، سرویس را نخواباند."""
    try:
        await asyncio.sleep(initial_delay)
        while True:
            try:
                await auto_release_once()
            except Exception as exc:
                log.warning("shop_autorelease_loop_error", error=str(exc))
            await asyncio.sleep(interval_seconds)
    except asyncio.CancelledError:
        pass
