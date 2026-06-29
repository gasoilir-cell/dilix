"""مدیریت اتصال‌های WebSocket — Presence و Fan-out رویداد.

هر کاربر می‌تواند چند اتصال همزمان (چند دستگاه) داشته باشد.
پیام‌ها به همه‌ی اتصال‌های فعال آن کاربر ارسال می‌شوند (fan-out).

در محیط multi-node باید fan-out از طریق NATS JetStream/pub-sub انجام شود.
اینجا پیاده‌سازی درون‌حافظه‌ای برای single-node است که قابل جایگزینی است.
"""
from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger("dilix.realtime")


class ConnectionManager:
    """مدیریت singleton اتصال‌های WebSocket."""

    def __init__(self) -> None:
        # earth_id → set of WebSocket connections
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        # earth_id → last_seen timestamp (presence)
        self._last_seen: dict[str, datetime] = {}

    # ─────────────────── lifecycle ───────────────────

    async def connect(self, ws: WebSocket, earth_id: str) -> None:
        await ws.accept()
        self._connections[earth_id].add(ws)
        self._last_seen[earth_id] = datetime.now(timezone.utc)
        logger.info("WS connect: %s (%d total)", earth_id, self.online_count)

        # اعلام حضور به دیگران
        await self.broadcast_presence(earth_id, online=True)

    async def disconnect(self, ws: WebSocket, earth_id: str) -> None:
        self._connections[earth_id].discard(ws)
        if not self._connections[earth_id]:
            del self._connections[earth_id]
        self._last_seen[earth_id] = datetime.now(timezone.utc)
        logger.info("WS disconnect: %s", earth_id)

        # اعلام آفلاین شدن
        if earth_id not in self._connections:
            await self.broadcast_presence(earth_id, online=False)

    # ─────────────────── send ─────────────────────────

    async def send_to(self, earth_id: str, payload: dict[str, Any]) -> int:
        """ارسال پیام به همه‌ی دستگاه‌های فعال یک کاربر. تعداد موفق را برمی‌گرداند."""
        sockets = list(self._connections.get(earth_id, set()))
        if not sockets:
            return 0

        text = json.dumps(payload, ensure_ascii=False, default=str)
        results = await asyncio.gather(
            *[_safe_send(ws, text) for ws in sockets], return_exceptions=True
        )
        sent = sum(1 for r in results if r is True)
        return sent

    async def broadcast_to_room(
        self,
        members: list[str],
        payload: dict[str, Any],
        exclude: str | None = None,
    ) -> None:
        """ارسال پیام به چند کاربر (مثلاً اعضای یک اتاق پیام)."""
        tasks = [
            self.send_to(mid, payload)
            for mid in members
            if mid != exclude
        ]
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def broadcast_presence(self, earth_id: str, online: bool) -> None:
        """اطلاع‌رسانی تغییر وضعیت حضور به همه (در پیاده‌سازی کامل: فقط دوستان/followerها)."""
        payload = {
            "type": "presence",
            "earth_id": earth_id,
            "online": online,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        for uid, sockets in list(self._connections.items()):
            if uid == earth_id:
                continue
            text = json.dumps(payload, ensure_ascii=False, default=str)
            await asyncio.gather(
                *[_safe_send(ws, text) for ws in sockets], return_exceptions=True
            )

    # ─────────────────── presence info ───────────────

    def is_online(self, earth_id: str) -> bool:
        return earth_id in self._connections and bool(self._connections[earth_id])

    def last_seen(self, earth_id: str) -> datetime | None:
        return self._last_seen.get(earth_id)

    @property
    def online_count(self) -> int:
        return len(self._connections)

    def online_users(self) -> list[str]:
        return list(self._connections.keys())


async def _safe_send(ws: WebSocket, text: str) -> bool:
    """ارسال ایمن — در صورت قطع اتصال، استثنا را نادیده می‌گیرد."""
    try:
        await ws.send_text(text)
        return True
    except Exception:
        return False


# Singleton — در main.py یک instance واحد ساخته می‌شود
manager = ConnectionManager()
