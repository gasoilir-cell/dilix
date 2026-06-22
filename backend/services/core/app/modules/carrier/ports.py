"""Port حمل‌ونقل — قراردادِ دامنه (ADR-02 / سند ۵).

Dilix متصدیِ حمل نیست؛ فقط به شرکتِ حملِ دارای مجوز وصل می‌شود. هر متصدی این
Port را پشتِ ACL پیاده می‌کند: create_waybill → track.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class WaybillRequest:
    shipment_ref: str
    shipper_ref: str
    origin: str
    destination: str
    weight_grams: int


@dataclass(frozen=True, slots=True)
class WaybillResult:
    waybill_no: str  # شماره‌ی بارنامه نزدِ متصدی
    status: str  # created | failed


@dataclass(frozen=True, slots=True)
class TrackingResult:
    waybill_no: str
    status: str  # dispatched | in_transit | delivered | cancelled
    last_location: str | None = None


class CarrierPort(ABC):
    """قراردادی که adapterهای متصدیِ حمل باید برآورده کنند."""

    @abstractmethod
    async def create_waybill(self, req: WaybillRequest) -> WaybillResult:
        """صدورِ بارنامه برای محموله."""

    @abstractmethod
    async def track(self, waybill_no: str) -> TrackingResult:
        """دریافتِ وضعیتِ زنده‌ی محموله از متصدی."""
