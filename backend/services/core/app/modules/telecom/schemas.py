from __future__ import annotations
import uuid
from pydantic import BaseModel, Field


class TopUpCreate(BaseModel):
    msisdn: str = Field(min_length=10, max_length=20)
    product_code: str
    amount_minor: int = Field(gt=0)
    currency: str = Field(default="IRR", min_length=3, max_length=3)
    provider_code: str = Field(default="sandbox")


class EsimCreate(BaseModel):
    iccid: str = Field(min_length=18, max_length=22)
    country_code: str = Field(min_length=2, max_length=4)
    provider_code: str = Field(default="sandbox")


class TopUpOut(BaseModel):
    id: uuid.UUID
    msisdn: str
    product_code: str
    amount_minor: int
    currency: str
    status: str
    external_ref: str | None
    model_config = {"from_attributes": True}


class EsimOut(BaseModel):
    id: uuid.UUID
    iccid: str
    country_code: str
    status: str
    model_config = {"from_attributes": True}
