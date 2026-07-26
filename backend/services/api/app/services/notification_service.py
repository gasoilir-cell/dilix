"""Notification service — orchestrates push + in-app notifications."""

from enum import Enum
import structlog
from app.providers.push.base import PushMessage, PushPriority
from app.providers.push.router import get_push_router

log = structlog.get_logger()


class NotificationChannel(str, Enum):
    PUSH = "push"
    IN_APP = "in_app"
    SMS = "sms"
    EMAIL = "email"


class NotificationPriority(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


PRIORITY_MAP = {
    NotificationPriority.CRITICAL: PushPriority.CRITICAL,
    NotificationPriority.HIGH: PushPriority.HIGH,
    NotificationPriority.MEDIUM: PushPriority.MEDIUM,
    NotificationPriority.LOW: PushPriority.LOW,
}

# Quiet hours: 22:00 — 08:00 local time
QUIET_HOUR_START = 22
QUIET_HOUR_END = 8

# Rate limit: max push notifications per user per day
PUSH_DAILY_LIMIT = 50


async def send_push(
    *,
    device_token: str,
    title: str,
    body: str,
    priority: NotificationPriority = NotificationPriority.MEDIUM,
    data: dict | None = None,
    image_url: str | None = None,
) -> bool:
    """Send a push notification via the router (Pushe or FCM)."""
    router = get_push_router()
    msg = PushMessage(
        device_token=device_token,
        title=title,
        body=body,
        priority=PRIORITY_MAP[priority],
        data=data or {},
        image_url=image_url,
    )
    result = await router.send(msg)
    if not result.success:
        log.warning("notification.push_failed", error=result.error, provider=result.provider)
    return result.success


# ── Pre-defined notification templates ──────────────────────────────────────

async def notify_otp(device_token: str, otp: str) -> bool:
    return await send_push(
        device_token=device_token,
        title="کد تأیید دیلیکس",
        body=f"کد ورود شما: {otp}",
        priority=NotificationPriority.CRITICAL,
    )


async def notify_shipment_matched(device_token: str, ref_id: str, driver_name: str) -> bool:
    return await send_push(
        device_token=device_token,
        title="راننده پیدا شد! 🚛",
        body=f"بار {ref_id} به {driver_name} واگذار شد",
        priority=NotificationPriority.HIGH,
        data={"type": "shipment_matched", "ref_id": ref_id},
    )


async def notify_payment_received(device_token: str, amount: str, currency: str) -> bool:
    return await send_push(
        device_token=device_token,
        title="پرداخت دریافت شد 💰",
        body=f"{amount} {currency} به کیف پول شما اضافه شد",
        priority=NotificationPriority.HIGH,
        data={"type": "payment_received"},
    )


async def notify_kyc_approved(device_token: str, level: int) -> bool:
    return await send_push(
        device_token=device_token,
        title="هویت شما تأیید شد ✅",
        body=f"سطح {level} تأیید هویت فعال شد",
        priority=NotificationPriority.HIGH,
        data={"type": "kyc_approved", "level": str(level)},
    )


async def notify_dispute_update(device_token: str, dispute_id: str, status: str) -> bool:
    return await send_push(
        device_token=device_token,
        title="به‌روزرسانی اختلاف",
        body=f"وضعیت اختلاف #{dispute_id}: {status}",
        priority=NotificationPriority.HIGH,
        data={"type": "dispute_update", "dispute_id": dispute_id},
    )
