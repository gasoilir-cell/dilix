"""
Dilix — سرویس OTP
ذخیره در Redis با TTL
"""
import structlog
from redis.asyncio import Redis

from app.core.config import settings
from app.core.security import generate_otp

log = structlog.get_logger(__name__)

OTP_PREFIX = "dilix:otp:"
ATTEMPT_PREFIX = "dilix:otp_attempts:"
COOLDOWN_PREFIX = "dilix:otp_cooldown:"


class OTPService:
    def __init__(self, redis: Redis):
        self.redis = redis

    async def send_otp(self, phone: str, purpose: str = "login") -> dict:
        """
        ارسال OTP به شماره موبایل
        returns: {"sent": True, "expires_in": 120, "masked_phone": "***1234"}
        """
        cooldown_key = f"{COOLDOWN_PREFIX}{phone}"
        if await self.redis.exists(cooldown_key):
            ttl = await self.redis.ttl(cooldown_key)
            return {
                "sent": False,
                "error": "too_soon",
                "retry_after": ttl,
                "message": f"لطفاً {ttl} ثانیه صبر کنید",
            }

        otp = generate_otp(settings.OTP_LENGTH)
        otp_key = f"{OTP_PREFIX}{phone}:{purpose}"

        # ذخیره در Redis با TTL
        await self.redis.setex(otp_key, settings.OTP_EXPIRE_SECONDS, otp)

        # cooldown 30 ثانیه برای جلوگیری از spam
        await self.redis.setex(cooldown_key, 30, "1")

        # ریست تعداد تلاش‌ها
        attempt_key = f"{ATTEMPT_PREFIX}{phone}"
        await self.redis.delete(attempt_key)

        # ارسال SMS
        await self._send_sms(phone, otp)

        masked = self._mask_phone(phone)
        log.info("otp_sent", phone_masked=masked, purpose=purpose)

        return {
            "sent": True,
            "expires_in": settings.OTP_EXPIRE_SECONDS,
            "masked_phone": masked,
            "message": f"کد تایید به {masked} ارسال شد",
        }

    async def verify_otp(self, phone: str, otp: str, purpose: str = "login") -> dict:
        """
        تایید OTP
        returns: {"valid": True/False, "reason": "..."}
        """
        attempt_key = f"{ATTEMPT_PREFIX}{phone}"
        attempts = await self.redis.incr(attempt_key)
        await self.redis.expire(attempt_key, settings.OTP_EXPIRE_SECONDS)

        if attempts > settings.OTP_MAX_ATTEMPTS:
            otp_key = f"{OTP_PREFIX}{phone}:{purpose}"
            await self.redis.delete(otp_key)
            log.warning("otp_max_attempts", phone_masked=self._mask_phone(phone))
            return {
                "valid": False,
                "reason": "max_attempts",
                "message": "تعداد تلاش‌ها بیش از حد مجاز. کد جدید درخواست دهید",
            }

        otp_key = f"{OTP_PREFIX}{phone}:{purpose}"
        stored_otp = await self.redis.get(otp_key)

        if not stored_otp:
            return {
                "valid": False,
                "reason": "expired",
                "message": "کد تایید منقضی شده است. کد جدید درخواست دهید",
            }

        # Redis ممکن است bytes برگرداند
        if isinstance(stored_otp, bytes):
            stored_otp = stored_otp.decode()

        if stored_otp != otp:
            remaining = settings.OTP_MAX_ATTEMPTS - attempts
            return {
                "valid": False,
                "reason": "invalid",
                "message": f"کد تایید اشتباه است. {remaining} تلاش باقی مانده",
            }

        # OTP معتبر — پاک کردن از Redis
        await self.redis.delete(otp_key)
        await self.redis.delete(attempt_key)

        log.info("otp_verified", phone_masked=self._mask_phone(phone))
        return {"valid": True}

    async def _send_sms(self, phone: str, otp: str) -> None:
        """ارسال SMS بر اساس provider تنظیم شده"""
        message = f"کد تایید دیلیکس: {otp}\nاین کد {settings.OTP_EXPIRE_SECONDS//60} دقیقه اعتبار دارد.\nبه کسی ندهید."

        if settings.SMS_PROVIDER == "console" or settings.is_development:
            # در dev — فقط در console نمایش
            log.info("OTP_CODE_DEV", phone=phone, otp=otp)
            print(f"\n{'='*50}")
            print(f"📱 OTP for {phone}: {otp}")
            print(f"{'='*50}\n")
            return

        # در production از SMSRouter استفاده می‌کند (Magfa یا Twilio بر اساس prefix)
        from app.providers.sms.router import get_sms_router
        from app.providers.sms.base import SMSMessage

        router = get_sms_router()
        result = await router.send(SMSMessage(to=phone, body=message))
        if not result.success:
            log.error("otp_sms_failed", phone_masked=self._mask_phone(phone), error=result.error)


    @staticmethod
    def _mask_phone(phone: str) -> str:
        if len(phone) <= 4:
            return "***"
        return f"{'*' * (len(phone) - 4)}{phone[-4:]}"
