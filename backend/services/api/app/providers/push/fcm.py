import httpx
import structlog
from app.providers.push.base import PushProvider, PushMessage, PushResult, PushPriority
from app.core.config import settings

log = structlog.get_logger()

PRIORITY_MAP = {
    PushPriority.CRITICAL: "high",
    PushPriority.HIGH: "high",
    PushPriority.MEDIUM: "normal",
    PushPriority.LOW: "normal",
}


class FCMProvider(PushProvider):
    """Firebase Cloud Messaging — for international users."""

    FCM_URL = "https://fcm.googleapis.com/fcm/send"

    def provider_name(self) -> str:
        return "fcm"

    async def send(self, message: PushMessage) -> PushResult:
        if not settings.FCM_SERVER_KEY:
            log.info("push.dev_mode", provider="fcm", title=message.title)
            return PushResult(success=True, message_id="dev-fcm", provider="fcm_dev")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    self.FCM_URL,
                    headers={
                        "Authorization": f"key={settings.FCM_SERVER_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "to": message.device_token,
                        "notification": {
                            "title": message.title,
                            "body": message.body,
                            "image": message.image_url,
                        },
                        "data": message.data,
                        "android": {"priority": PRIORITY_MAP[message.priority]},
                        "apns": {
                            "headers": {"apns-priority": "10" if message.priority in (PushPriority.CRITICAL, PushPriority.HIGH) else "5"}
                        },
                    },
                )
                data = resp.json()
                if data.get("success") == 1:
                    return PushResult(success=True, message_id=data.get("results", [{}])[0].get("message_id"), provider="fcm")
                return PushResult(success=False, error=str(data.get("results")), provider="fcm")
        except Exception as exc:
            log.error("push.fcm_error", error=str(exc))
            return PushResult(success=False, error=str(exc), provider="fcm")
