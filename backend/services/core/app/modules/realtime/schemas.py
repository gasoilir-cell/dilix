"""Schemaهای Realtime WebSocket — رویدادهای دریافتی و ارسالی (سند ۵)."""
from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel


class WsEventType(str, Enum):
    # پیام‌رسان
    MESSAGE_NEW = "message.new"
    MESSAGE_DELETED = "message.deleted"
    MESSAGE_READ = "message.read"
    TYPING_START = "typing.start"
    TYPING_STOP = "typing.stop"
    # حضور
    PRESENCE = "presence"
    # اعلان
    NOTIFICATION = "notification"
    # بار/حمل
    FREIGHT_UPDATE = "freight.update"
    LOCATION_UPDATE = "location.update"
    # تماس صوتی/تصویری (WebRTC signaling — سند ۵ §۵)
    CALL_OFFER = "call.offer"
    CALL_ANSWER = "call.answer"
    CALL_END = "call.end"
    ICE_CANDIDATE = "ice.candidate"
    # سیستم
    PING = "ping"
    PONG = "pong"
    ERROR = "error"


class WsIncoming(BaseModel):
    """پیام ورودی از کلاینت."""
    type: WsEventType
    payload: dict[str, Any] = {}


class WsOutgoing(BaseModel):
    """پیام خروجی به کلاینت."""
    type: WsEventType
    payload: dict[str, Any] = {}
    ts: str = ""


class PresenceResponse(BaseModel):
    earth_id: str
    online: bool
    last_seen: str | None = None
