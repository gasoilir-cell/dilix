"""Port بیمه — قراردادِ دامنه (ADR-02 / سند ۵).

Dilix بیمه‌گر نیست؛ فقط به بیمه‌گرِ دارای مجوز (بیمه البرز، ...) وصل می‌شود.
هر بیمه‌گر این Port را پشتِ ACL پیاده می‌کند: quote → issue → claim.
مبالغ بر حسبِ کوچک‌ترین واحدِ پول (ریال/سِنت) هستند.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class QuoteRequest:
    product_code: str
    holder_ref: str
    coverage_minor: int
    currency: str
    attributes: dict


@dataclass(frozen=True, slots=True)
class QuoteResult:
    quote_ref: str
    premium_minor: int
    currency: str


@dataclass(frozen=True, slots=True)
class IssueResult:
    external_ref: str  # شماره‌ی بیمه‌نامه نزدِ بیمه‌گر
    status: str  # issued | failed


@dataclass(frozen=True, slots=True)
class ClaimResult:
    claim_ref: str
    status: str  # registered | rejected


class InsurancePort(ABC):
    """قراردادی که adapterهای بیمه‌گر باید برآورده کنند."""

    @abstractmethod
    async def quote(self, req: QuoteRequest) -> QuoteResult:
        """محاسبه‌ی حقِ بیمه برای پوششِ درخواستی."""

    @abstractmethod
    async def issue(self, quote_ref: str) -> IssueResult:
        """صدورِ بیمه‌نامه از روی quote معتبر."""

    @abstractmethod
    async def claim(self, external_ref: str, amount_minor: int, reason: str) -> ClaimResult:
        """ثبتِ خسارت روی بیمه‌نامه‌ی صادرشده."""
