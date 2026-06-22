"""Port تلکام — eSIM / شارژ / استعلامِ بسته (ADR-02)."""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TopUpRequest:
    subscriber_ref: str
    msisdn: str       # شماره‌ی موبایل
    amount_minor: int
    currency: str
    product_code: str  # «۱GB-30day»، «Voice-200min»، …


@dataclass(frozen=True, slots=True)
class TopUpResult:
    external_ref: str
    status: str  # success | pending | failed
    balance_after_minor: int | None = None


@dataclass(frozen=True, slots=True)
class EsimActivationRequest:
    subscriber_ref: str
    iccid: str
    country_code: str


@dataclass(frozen=True, slots=True)
class EsimActivationResult:
    iccid: str
    status: str  # activated | failed


class TelecomPort(ABC):
    @abstractmethod
    async def top_up(self, req: TopUpRequest) -> TopUpResult: ...

    @abstractmethod
    async def activate_esim(self, req: EsimActivationRequest) -> EsimActivationResult: ...
