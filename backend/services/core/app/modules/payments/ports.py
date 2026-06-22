"""Port پرداخت — قراردادِ دامنه برای escrow (ADR-07).

مدلِ کسب‌وکار: Dilix **پول نگه نمی‌دارد**؛ فقط ارکستریت می‌کند. وجه نزدِ بانکِ
دارای مجوز در حسابِ امانی (escrow) می‌نشیند و فقط با دستورِ release آزاد می‌شود.
این Port را هر ارائه‌دهنده‌ی پرداخت (سامان، ...) پیاده می‌کند.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class EscrowRequest:
    """درخواستِ ایجادِ امانت. مبلغ به کوچک‌ترین واحد (ریال/سِنت) است."""

    order_ref: str
    amount_minor: int
    currency: str
    payer_ref: str
    payee_ref: str


@dataclass(frozen=True, slots=True)
class EscrowResult:
    """نتیجه‌ی سمتِ ارائه‌دهنده. `external_ref` شناسه‌ی امانت نزدِ بانک است."""

    external_ref: str
    status: str  # held | failed
    redirect_url: str | None = None


@dataclass(frozen=True, slots=True)
class SettlementResult:
    external_ref: str
    status: str  # captured | refunded | failed


class PaymentPort(ABC):
    """قراردادی که adapterهای ارائه‌دهنده باید برآورده کنند (پشتِ ACL)."""

    @abstractmethod
    async def create_escrow(self, req: EscrowRequest) -> EscrowResult:
        """بلوکه‌کردنِ وجهِ پرداخت‌کننده در حسابِ امانیِ بانک."""

    @abstractmethod
    async def capture(self, external_ref: str) -> SettlementResult:
        """آزادسازیِ امانت به نفعِ دریافت‌کننده (پس از تأییدِ تحویل)."""

    @abstractmethod
    async def refund(self, external_ref: str) -> SettlementResult:
        """بازگردانیِ امانت به پرداخت‌کننده (لغو/اختلاف)."""
