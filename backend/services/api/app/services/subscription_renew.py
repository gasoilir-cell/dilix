"""
Dilix — تمدیدِ خودکارِ اشتراکِ سازندگان (فاز ۴)

بدونِ این حلقه، پرچمِ `auto_renew` فقط یک تیکِ تزئینی در UI بود: اشتراک سرِ
موعد تمام می‌شد و هیچ‌وقت خودش تمدید نمی‌شد.

قواعد:
    * فقط اشتراک‌هایی که `auto_renew` دارند و دوره‌شان سررسید شده.
    * پرداخت با همان روالِ اتمیکِ کیفِ پول؛ اگر موجودی کم بود یا پلن غیرفعال
      شده بود، اشتراک `expired` می‌شود — نه اینکه بی‌سروصدا ادامه پیدا کند.
    * هر اشتراک در تراکنشِ خودش پردازش می‌شود تا شکستِ یکی بقیه را نبَرَد.
"""
import asyncio
from datetime import datetime, timezone

import structlog
from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal

log = structlog.get_logger(__name__)


async def renew_due_once() -> int:
    """یک دورِ تمدید؛ تعدادِ اشتراک‌های تمدیدشده را برمی‌گرداند."""
    from app.api.v1.business.subscriptions import (
        Subscription, SubscriptionCharge, SubscriptionTier, _charge_period,
    )
    from app.models.user import User

    now = datetime.now(timezone.utc)
    renewed = 0

    async with AsyncSessionLocal() as db:
        due = (await db.execute(
            select(Subscription).where(
                Subscription.auto_renew.is_(True),
                Subscription.status == "active",
                Subscription.current_period_end <= now,
            ).limit(500)
        )).scalars().all()
        due_ids = [s.id for s in due]

    for sub_id in due_ids:
        async with AsyncSessionLocal() as db:
            try:
                s = await db.get(Subscription, sub_id)
                if s is None or not s.auto_renew or s.status != "active":
                    continue
                if s.current_period_end > now:
                    continue

                tier = await db.get(SubscriptionTier, s.tier_id)
                owner = await db.get(User, s.owner_id)
                subscriber = await db.get(User, s.subscriber_id)
                if tier is None or not tier.is_active or owner is None or subscriber is None:
                    s.status = "expired"
                    await db.commit()
                    continue

                period_no = int((await db.execute(
                    select(func.count()).select_from(SubscriptionCharge)
                    .where(SubscriptionCharge.subscription_id == s.id)
                )).scalar() or 0) + 1

                await _charge_period(db, s, tier, owner, subscriber, period_no,
                                     s.current_period_end)
                await db.commit()
                renewed += 1
            except Exception as exc:
                # موجودیِ ناکافی هم از همین‌جا می‌آید (HTTPException 400).
                await db.rollback()
                try:
                    s = await db.get(Subscription, sub_id)
                    if s is not None and s.status == "active":
                        s.status = "expired"
                        await db.commit()
                except Exception:
                    await db.rollback()
                log.info("subscription_renew_failed", subscription_id=str(sub_id),
                         error=str(exc))

    if renewed:
        log.info("subscriptions_renewed", count=renewed)
    return renewed


async def periodic_subscription_renew(interval_seconds: int = 3600,
                                      initial_delay: int = 40) -> None:
    """حلقهٔ ساعتیِ تمدید؛ در lifespan به‌صورتِ task اجرا می‌شود و هرگز استثنا
    بیرون نمی‌دهد تا خطای یک دور، سرویس را نخواباند."""
    try:
        await asyncio.sleep(initial_delay)
        while True:
            try:
                await renew_due_once()
            except Exception as exc:
                log.warning("subscription_renew_loop_error", error=str(exc))
            await asyncio.sleep(interval_seconds)
    except asyncio.CancelledError:
        pass
