"""DTOهای API پرداخت (Pydantic). مبلغ بر حسبِ کوچک‌ترین واحدِ پول است."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class EscrowCreate(BaseModel):
    payee_earth_id: uuid.UUID
    amount_minor: int = Field(gt=0, description="مبلغ به کوچک‌ترین واحد (ریال/سِنت)")
    currency: str = Field(min_length=3, max_length=3, description="کدِ ISO 4217، مثل IRR")
    provider_code: str = Field(default="sandbox")


class PaymentOrderOut(BaseModel):
    id: uuid.UUID
    payer_earth_id: uuid.UUID
    payee_earth_id: uuid.UUID
    amount_minor: int
    currency: str
    provider_code: str
    external_ref: str | None
    status: str

    model_config = {"from_attributes": True}
