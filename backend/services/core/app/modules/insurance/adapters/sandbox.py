"""Adapterِ نمونه (Sandbox) بیمه — بدون اتصالِ بیمه‌گرِ واقعی.

حقِ بیمه را به‌صورتِ نسبتِ ثابت از پوشش محاسبه می‌کند تا جریانِ دامنه و رویدادها
بدونِ وابستگیِ بیرونی تست‌پذیر باشد. حالت در حافظه نگه‌داری می‌شود.
"""
from __future__ import annotations

import uuid

from dilix_shared.adapter import AdapterError

from app.modules.insurance.ports import (
    ClaimResult,
    InsurancePort,
    IssueResult,
    QuoteRequest,
    QuoteResult,
)

# نرخِ نمونه: حقِ بیمه = ۲٪ مبلغِ پوشش
_PREMIUM_RATE_BPS = 200  # basis points


class SandboxInsuranceAdapter(InsurancePort):
    def __init__(self) -> None:
        self._quotes: dict[str, int] = {}  # quote_ref → premium_minor
        self._policies: set[str] = set()  # external_refهای صادرشده

    async def quote(self, req: QuoteRequest) -> QuoteResult:
        if req.coverage_minor <= 0:
            raise AdapterError("invalid_coverage", "مبلغ پوشش باید مثبت باشد.")
        premium = max(1, req.coverage_minor * _PREMIUM_RATE_BPS // 10_000)
        quote_ref = f"qte_{uuid.uuid4().hex[:16]}"
        self._quotes[quote_ref] = premium
        return QuoteResult(quote_ref=quote_ref, premium_minor=premium, currency=req.currency)

    async def issue(self, quote_ref: str) -> IssueResult:
        if quote_ref not in self._quotes:
            raise AdapterError("quote_not_found", f"quote یافت نشد: {quote_ref}")
        external_ref = f"pol_{uuid.uuid4().hex[:16]}"
        self._policies.add(external_ref)
        return IssueResult(external_ref=external_ref, status="issued")

    async def claim(self, external_ref: str, amount_minor: int, reason: str) -> ClaimResult:
        if external_ref not in self._policies:
            raise AdapterError("policy_not_found", f"بیمه‌نامه یافت نشد: {external_ref}")
        if amount_minor <= 0:
            raise AdapterError("invalid_amount", "مبلغ خسارت باید مثبت باشد.")
        return ClaimResult(claim_ref=f"clm_{uuid.uuid4().hex[:16]}", status="registered")
