import structlog
from app.providers.sms.base import SMSProvider, SMSMessage, SMSResult
from app.providers.sms.magfa import MagfaProvider
from app.providers.sms.twilio import TwilioProvider

log = structlog.get_logger()


class SMSRouter(SMSProvider):
    """Routes SMS to the correct provider based on phone number prefix.

    Iran (+98) → Magfa
    International → Twilio
    """

    def __init__(self) -> None:
        self._providers: list[SMSProvider] = [
            MagfaProvider(),
            TwilioProvider(),
        ]

    def supports_number(self, phone: str) -> bool:
        return True  # Router handles all numbers

    async def send(self, message: SMSMessage) -> SMSResult:
        provider = self._select(message.to)
        if provider is None:
            return SMSResult(success=False, error="No provider for this number", provider="none")

        result = await provider.send(message)
        log.info("sms.sent", to=message.to, provider=result.provider, success=result.success)
        return result

    def _select(self, phone: str) -> SMSProvider | None:
        for p in self._providers:
            if p.supports_number(phone):
                return p
        return None


# Singleton
_router: SMSRouter | None = None


def get_sms_router() -> SMSRouter:
    global _router
    if _router is None:
        _router = SMSRouter()
    return _router
