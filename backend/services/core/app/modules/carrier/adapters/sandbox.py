"""Adapterِ نمونه (Sandbox) حمل‌ونقل — بدون اتصالِ متصدیِ واقعی.

بارنامه صادر می‌کند و وضعیتِ ساختگیِ in_transit برمی‌گرداند تا جریانِ دامنه و
رویدادها بدونِ وابستگیِ بیرونی تست‌پذیر باشد.
"""
from __future__ import annotations

import uuid

from dilix_shared.adapter import AdapterError

from app.modules.carrier.ports import (
    CarrierPort,
    TrackingResult,
    WaybillRequest,
    WaybillResult,
)


class SandboxCarrierAdapter(CarrierPort):
    def __init__(self) -> None:
        self._waybills: set[str] = set()

    async def create_waybill(self, req: WaybillRequest) -> WaybillResult:
        if req.weight_grams <= 0:
            raise AdapterError("invalid_weight", "وزن باید مثبت باشد.")
        if not req.origin or not req.destination:
            raise AdapterError("invalid_route", "مبدأ و مقصد لازم است.")
        waybill_no = f"wb_{uuid.uuid4().hex[:16]}"
        self._waybills.add(waybill_no)
        return WaybillResult(waybill_no=waybill_no, status="created")

    async def track(self, waybill_no: str) -> TrackingResult:
        if waybill_no not in self._waybills:
            raise AdapterError("not_found", f"بارنامه یافت نشد: {waybill_no}")
        return TrackingResult(
            waybill_no=waybill_no, status="in_transit", last_location="hub-1"
        )
