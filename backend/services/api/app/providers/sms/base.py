from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class SMSMessage:
    to: str          # E.164 format, e.g. +989120000000
    body: str
    template_id: str | None = None
    variables: dict | None = None


@dataclass
class SMSResult:
    success: bool
    message_id: str | None = None
    error: str | None = None
    provider: str = ""


class SMSProvider(ABC):
    """Abstract SMS provider port."""

    @abstractmethod
    async def send(self, message: SMSMessage) -> SMSResult:
        ...

    @abstractmethod
    def supports_number(self, phone: str) -> bool:
        """Return True if this provider can send to the given phone number."""
        ...
