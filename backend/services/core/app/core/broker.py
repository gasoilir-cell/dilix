"""اتصال به NATS JetStream — لایه‌ی انتقالِ Event Backbone (ADR-04 / سند ۴).

این ماژول فقط «انتقال» را می‌داند؛ منطقِ اتمیک‌بودن در Outbox است. اتصال
تنبل (lazy) و اختیاری است تا تست‌ها و اجرای آفلاین به broker نیاز نداشته باشند.
"""
from __future__ import annotations

import logging

from app.core.config import get_settings

logger = logging.getLogger("dilix.broker")

# نامِ stream و الگوی subject. هر رویداد روی `dilix.events.<name>` منتشر می‌شود.
STREAM_NAME = "DILIX_EVENTS"
SUBJECT_PREFIX = "dilix.events"


class JetStreamBroker:
    """پوشش نازک روی nats-py با تضمینِ وجودِ stream (idempotent)."""

    def __init__(self, url: str | None = None) -> None:
        self._url = url or get_settings().event_broker_url
        self._nc = None  # nats.aio.client.Client
        self._js = None  # JetStreamContext

    async def connect(self) -> None:
        if self._nc is not None:
            return
        import nats  # import تنبل تا وابستگی فقط هنگام اجرای واقعی لازم شود

        self._nc = await nats.connect(self._url)
        self._js = self._nc.jetstream()
        await self._ensure_stream()
        logger.info("broker.connected url=%s stream=%s", self._url, STREAM_NAME)

    async def _ensure_stream(self) -> None:
        from nats.js.errors import NotFoundError as JsNotFound

        try:
            await self._js.stream_info(STREAM_NAME)
        except JsNotFound:
            await self._js.add_stream(name=STREAM_NAME, subjects=[f"{SUBJECT_PREFIX}.>"])
            logger.info("broker.stream_created name=%s", STREAM_NAME)

    async def publish(self, name: str, body: bytes, *, msg_id: str) -> None:
        """انتشار با msg_id برای dedup سمتِ JetStream (دقیقاً-یک-بار مؤثر)."""
        if self._js is None:
            await self.connect()
        subject = f"{SUBJECT_PREFIX}.{name}"
        await self._js.publish(subject, body, headers={"Nats-Msg-Id": msg_id})

    async def close(self) -> None:
        if self._nc is not None:
            await self._nc.drain()
            self._nc = None
            self._js = None


broker = JetStreamBroker()
