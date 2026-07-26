import httpx
import structlog
from app.providers.sms.base import SMSProvider, SMSMessage, SMSResult
from app.core.config import settings

log = structlog.get_logger()

IRAN_PREFIXES = ("+98",)


class TwilioProvider(SMSProvider):
    """Twilio SMS — for international numbers (non-Iran)."""

    BASE_URL = "https://api.twilio.com/2010-04-01"

    def supports_number(self, phone: str) -> bool:
        return not phone.startswith(IRAN_PREFIXES)

    async def send(self, message: SMSMessage) -> SMSResult:
        if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
            log.info("sms.dev_mode", to=message.to, body=message.body)
            return SMSResult(success=True, message_id="dev-twilio", provider="twilio_dev")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    f"{self.BASE_URL}/Accounts/{settings.TWILIO_ACCOUNT_SID}/Messages.json",
                    auth=(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN),
                    data={
                        "From": settings.TWILIO_PHONE_NUMBER,
                        "To": message.to,
                        "Body": message.body,
                    },
                )
                data = resp.json()
                if resp.status_code in (200, 201):
                    return SMSResult(success=True, message_id=data.get("sid"), provider="twilio")
                return SMSResult(success=False, error=data.get("message"), provider="twilio")
        except Exception as exc:
            log.error("sms.twilio_error", error=str(exc))
            return SMSResult(success=False, error=str(exc), provider="twilio")
