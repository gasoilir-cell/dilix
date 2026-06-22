"""DTOهای API حمل‌ونقل (Pydantic)."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class ShipmentCreate(BaseModel):
    origin: str = Field(min_length=1, max_length=120)
    destination: str = Field(min_length=1, max_length=120)
    weight_grams: int = Field(gt=0)
    provider_code: str = Field(default="sandbox")


class ShipmentOut(BaseModel):
    id: uuid.UUID
    shipper_earth_id: uuid.UUID
    provider_code: str
    origin: str
    destination: str
    weight_grams: int
    waybill_no: str | None
    status: str
    last_location: str | None

    model_config = {"from_attributes": True}
