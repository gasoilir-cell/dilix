"""Push notification router.

Token prefix convention:
  pushe:xxxxxxx  → route to Pushe.ir
  fcm:xxxxxxx    → route to FCM
  (no prefix)    → default to FCM
"""

import structlog
from app.providers.push.base import PushProvider, PushMessage, PushResult
from app.providers.push.pushe import PusheProvider
from app.providers.push.fcm import FCMProvider

log = structlog.get_logger()


class PushRouter(PushProvider):
    def __init__(self) -> None:
        self._pushe = PusheProvider()
        self._fcm = FCMProvider()

    def provider_name(self) -> str:
        return "router"

    async def send(self, message: PushMessage) -> PushResult:
        token = message.device_token

        if token.startswith("pushe:"):
            message.device_token = token[6:]
            return await self._pushe.send(message)

        if token.startswith("fcm:"):
            message.device_token = token[4:]

        return await self._fcm.send(message)


_router: PushRouter | None = None


def get_push_router() -> PushRouter:
    global _router
    if _router is None:
        _router = PushRouter()
    return _router
