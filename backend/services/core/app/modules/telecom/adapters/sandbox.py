"""Adapterِ sandbox تلکام."""
from __future__ import annotations
import uuid
from dilix_shared.adapter import AdapterError
from app.modules.telecom.ports import (
    EsimActivationRequest, EsimActivationResult,
    TelecomPort, TopUpRequest, TopUpResult,
)


class SandboxTelecomAdapter(TelecomPort):
    async def top_up(self, req: TopUpRequest) -> TopUpResult:
        if req.amount_minor <= 0:
            raise AdapterError("invalid_amount", "مبلغ باید مثبت باشد.")
        return TopUpResult(
            external_ref=f"tu_{uuid.uuid4().hex[:12]}",
            status="success",
            balance_after_minor=req.amount_minor,
        )

    async def activate_esim(self, req: EsimActivationRequest) -> EsimActivationResult:
        if len(req.iccid) < 18:
            raise AdapterError("invalid_iccid", "ICCID نامعتبر است.")
        return EsimActivationResult(iccid=req.iccid, status="activated")
