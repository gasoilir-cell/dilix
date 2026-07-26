from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum


class PushPriority(str, Enum):
    CRITICAL = "critical"   # payment, safety
    HIGH = "high"           # new bid, match
    MEDIUM = "medium"       # message, update
    LOW = "low"             # promo, tip


@dataclass
class PushMessage:
    device_token: str
    title: str
    body: str
    priority: PushPriority = PushPriority.MEDIUM
    data: dict = field(default_factory=dict)
    image_url: str | None = None
    action_url: str | None = None


@dataclass
class PushResult:
    success: bool
    message_id: str | None = None
    error: str | None = None
    provider: str = ""


class PushProvider(ABC):
    """Abstract push notification provider port."""

    @abstractmethod
    async def send(self, message: PushMessage) -> PushResult:
        ...

    @abstractmethod
    def provider_name(self) -> str:
        ...
