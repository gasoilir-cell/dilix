"""Adapterِ نمونه (Sandbox) برای پرداخت — بدون اتصالِ بانکِ واقعی.

رفتارِ یک بانکِ escrow را شبیه‌سازی می‌کند تا کلِ جریانِ دامنه و رویدادها بدونِ
وابستگیِ بیرونی تست‌پذیر باشد. حالت در حافظه نگه‌داری می‌شود.
"""
from __future__ import annotations

import uuid

from dilix_shared.adapter import AdapterError

from app.modules.payments.ports import (
    EscrowRequest,
    EscrowResult,
    PaymentPort,
    SettlementResult,
)


class SandboxPaymentAdapter(PaymentPort):
    def __init__(self) -> None:
        # external_ref → وضعیت فعلیِ امانت
        self._escrows: dict[str, str] = {}

    async def create_escrow(self, req: EscrowRequest) -> EscrowResult:
        if req.amount_minor <= 0:
            raise AdapterError("invalid_amount", "مبلغ باید مثبت باشد.")
        external_ref = f"sbx_{uuid.uuid4().hex[:16]}"
        self._escrows[external_ref] = "held"
        return EscrowResult(external_ref=external_ref, status="held")

    async def capture(self, external_ref: str) -> SettlementResult:
        self._require(external_ref, expected="held")
        self._escrows[external_ref] = "captured"
        return SettlementResult(external_ref=external_ref, status="captured")

    async def refund(self, external_ref: str) -> SettlementResult:
        self._require(external_ref, expected="held")
        self._escrows[external_ref] = "refunded"
        return SettlementResult(external_ref=external_ref, status="refunded")

    def _require(self, external_ref: str, *, expected: str) -> None:
        current = self._escrows.get(external_ref)
        if current is None:
            raise AdapterError("not_found", f"امانت یافت نشد: {external_ref}")
        if current != expected:
            raise AdapterError(
                "invalid_state", f"وضعیتِ امانت '{current}' است نه '{expected}'."
            )
