"""Adapterِ بانک سامان برای پرداخت (مدلِ escrow/پرداخت‌یاریِ شاپرک، ADR-07).

Dilix وجه نگه نمی‌دارد؛ این adapter فقط دستورِ ایجاد/آزادسازی/بازگشتِ امانت را به
درگاهِ بانک می‌فرستد. مسیرها و نام‌فیلدهای دقیق باید با قراردادِ رسمیِ بانک تطبیق
داده شوند؛ این پیاده‌سازی الگوی امن (امضای HMAC + Idempotency-Key) را می‌دهد.

نکته: فقط وقتی `DILIX_SAMAN_BASE_URL` و `DILIX_SAMAN_SECRET` تنظیم باشند ثبت می‌شود
(در `adapters/__init__.py`).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import uuid

from dilix_shared.adapter import AdapterError

from app.modules.payments.ports import (
    EscrowRequest,
    EscrowResult,
    PaymentPort,
    SettlementResult,
)


def build_escrow_payload(req: EscrowRequest) -> dict:
    """نگاشتِ درخواستِ دامنه به بدنه‌ی موردِ انتظارِ درگاه (Anti-Corruption Layer)."""
    return {
        "order_id": req.order_ref,
        "amount": req.amount_minor,
        "currency": req.currency,
        "payer": req.payer_ref,
        "payee": req.payee_ref,
    }


def sign_body(secret: str, body: dict) -> str:
    """امضای HMAC-SHA256 روی بدنه‌ی JSONِ مرتب‌شده (ضدِ دستکاری)."""
    raw = json.dumps(body, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hmac.new(secret.encode("utf-8"), raw, hashlib.sha256).hexdigest()


class SamanPaymentAdapter(PaymentPort):
    def __init__(self, base_url: str, terminal_id: str, secret: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._terminal_id = terminal_id
        self._secret = secret

    async def _post(self, path: str, body: dict) -> dict:
        import httpx  # importِ تنبل تا فقط هنگامِ اجرای واقعی لازم شود

        headers = {
            "X-Terminal-Id": self._terminal_id,
            "X-Signature": sign_body(self._secret, body),
            "Idempotency-Key": str(uuid.uuid4()),
            "Content-Type": "application/json",
        }
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(f"{self._base_url}{path}", json=body, headers=headers)
        except httpx.HTTPError as exc:  # خطای شبکه → قابلِ retry
            raise AdapterError("network", str(exc), retryable=True) from exc
        if resp.status_code >= 500:
            raise AdapterError("upstream_5xx", resp.text[:200], retryable=True)
        if resp.status_code >= 400:
            raise AdapterError("upstream_4xx", resp.text[:200])
        return resp.json()

    async def create_escrow(self, req: EscrowRequest) -> EscrowResult:
        data = await self._post("/escrow", build_escrow_payload(req))
        return EscrowResult(
            external_ref=data["reference"],
            status=data.get("status", "held"),
            redirect_url=data.get("redirect_url"),
        )

    async def capture(self, external_ref: str) -> SettlementResult:
        data = await self._post("/escrow/capture", {"reference": external_ref})
        return SettlementResult(external_ref=external_ref, status=data.get("status", "captured"))

    async def refund(self, external_ref: str) -> SettlementResult:
        data = await self._post("/escrow/refund", {"reference": external_ref})
        return SettlementResult(external_ref=external_ref, status=data.get("status", "refunded"))
