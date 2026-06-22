"""DTOهای API بیمه (Pydantic). مبالغ بر حسبِ کوچک‌ترین واحدِ پول."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class QuoteCreate(BaseModel):
    product_code: str = Field(min_length=1, max_length=64)
    coverage_minor: int = Field(gt=0, description="مبلغ پوشش به کوچک‌ترین واحد")
    currency: str = Field(min_length=3, max_length=3)
    provider_code: str = Field(default="sandbox")
    attributes: dict = Field(default_factory=dict)


class ClaimCreate(BaseModel):
    amount_minor: int = Field(gt=0)
    reason: str = Field(min_length=1, max_length=500)


class PolicyOut(BaseModel):
    id: uuid.UUID
    holder_earth_id: uuid.UUID
    provider_code: str
    product_code: str
    coverage_minor: int
    premium_minor: int
    currency: str
    external_ref: str | None
    status: str

    model_config = {"from_attributes": True}
