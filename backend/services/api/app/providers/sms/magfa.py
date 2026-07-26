import httpx
import structlog
from app.providers.sms.base import SMSProvider, SMSMessage, SMSResult
from app.core.config import settings

log = structlog.get_logger()

IRAN_PREFIXES = ("+98",)


class MagfaProvider(SMSProvider):
    """Magfa SMS — for Iranian phone numbers (+98)."""

    BASE_URL = "https://sms.magfa.com/api/http/sms/v2"

    def supports_number(self, phone: str) -> bool:
        return phone.startswith(IRAN_PREFIXES)

    async def send(self, message: SMSMessage) -> SMSResult:
        if not settings.MAGFA_USERNAME or not settings.MAGFA_PASSWORD:
            # Dev fallback — print to console
            log.info("sms.dev_mode", to=message.to, body=message.body)
            return SMSResult(success=True, message_id="dev-magfa", provider="magfa_dev")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    f"{self.BASE_URL}/send",
                    auth=(settings.MAGFA_USERNAME, settings.MAGFA_PASSWORD),
                    json={
                        "senders": [settings.MAGFA_SENDER],
                        "recipients": [message.to.replace("+98", "0")],
                        "messages": [message.body],
                    },
                )
                data = resp.json()
                if data.get("status") == 1:
                    return SMSResult(
                        success=True,
                        message_id=str(data.get("messages", [{}])[0].get("id")),
                        provider="magfa",
                    )
                return SMSResult(success=False, error=str(data), provider="magfa")
        except Exception as exc:
            log.error("sms.magfa_error", error=str(exc))
            return SMSResult(success=False, error=str(exc), provider="magfa")
