import httpx
import structlog
from app.providers.push.base import PushProvider, PushMessage, PushResult, PushPriority
from app.core.config import settings

log = structlog.get_logger()

PRIORITY_MAP = {
    PushPriority.CRITICAL: "high",
    PushPriority.HIGH: "high",
    PushPriority.MEDIUM: "normal",
    PushPriority.LOW: "low",
}


class PusheProvider(PushProvider):
    """Pushe.ir — for Iran (works without Google Play Services / FCM blocked)."""

    BASE_URL = "https://api.pushe.co/v2"

    def provider_name(self) -> str:
        return "pushe"

    async def send(self, message: PushMessage) -> PushResult:
        if not settings.PUSHE_TOKEN:
            log.info("push.dev_mode", provider="pushe", title=message.title)
            return PushResult(success=True, message_id="dev-pushe", provider="pushe_dev")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    f"{self.BASE_URL}/messaging/send/",
                    headers={"Authorization": f"Token {settings.PUSHE_TOKEN}"},
                    json={
                        "app_ids": [settings.PUSHE_APP_ID],
                        "filters": {"registration_ids": [message.device_token]},
                        "notification": {
                            "title": message.title,
                            "content": message.body,
                            "image": message.image_url,
                        },
                        "data": message.data,
                        "android": {"priority": PRIORITY_MAP[message.priority]},
                    },
                )
                data = resp.json()
                if resp.status_code == 200:
                    return PushResult(success=True, message_id=data.get("id"), provider="pushe")
                return PushResult(success=False, error=str(data), provider="pushe")
        except Exception as exc:
            log.error("push.pushe_error", error=str(exc))
            return PushResult(success=False, error=str(exc), provider="pushe")
