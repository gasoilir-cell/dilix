from __future__ import annotations
import uuid
from pydantic import BaseModel, Field


class BuyRequest(BaseModel):
    fund_code: str
    amount_minor: int = Field(gt=0)
    currency: str = Field(default="IRR", min_length=3, max_length=3)
    provider_code: str = Field(default="sandbox_fund")


class SellRequest(BaseModel):
    position_id: uuid.UUID
    units: float = Field(gt=0)


class NavOut(BaseModel):
    fund_code: str
    nav_minor: int


class PositionOut(BaseModel):
    id: uuid.UUID
    fund_code: str
    units: float
    status: str
    model_config = {"from_attributes": True}
