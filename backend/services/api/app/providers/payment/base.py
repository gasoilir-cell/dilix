from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum


class PaymentStatus(str, Enum):
    PENDING = "pending"
    SUCCESS = "success"
    FAILED = "failed"
    REFUNDED = "refunded"


@dataclass
class PaymentRequest:
    amount: int           # in smallest unit (Rial for Iran, cents for USD)
    currency: str         # IRR, USD, EUR, ...
    description: str
    user_id: str
    callback_url: str
    metadata: dict | None = None


@dataclass
class PaymentResult:
    success: bool
    status: PaymentStatus
    payment_url: str | None = None   # redirect user here
    authority: str | None = None     # gateway reference
    ref_id: str | None = None        # final ref after verify
    error: str | None = None
    provider: str = ""


class PaymentProvider(ABC):
    """Abstract payment provider port."""

    @abstractmethod
    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        """Start a payment → returns redirect URL."""
        ...

    @abstractmethod
    async def verify(self, authority: str, amount: int) -> PaymentResult:
        """Verify a payment after callback."""
        ...

    @abstractmethod
    def supports_currency(self, currency: str) -> bool:
        ...
