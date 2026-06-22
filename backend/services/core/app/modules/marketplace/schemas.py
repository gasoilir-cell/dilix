"""Schemaهای Marketplace (سند ۵)."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class ListingCreate(BaseModel):
    title: str = Field(min_length=5, max_length=200)
    description: str = Field(min_length=10)
    category: str = Field(max_length=32)
    base_price_minor: int = Field(gt=0)
    currency: str = Field(default="IRR", min_length=3, max_length=3)
    delivery_days: int = Field(default=7, ge=1, le=365)
    tags: list[str] = Field(default_factory=list)
    media_refs: list[str] = Field(default_factory=list)


class ListingOut(BaseModel):
    id: uuid.UUID
    provider_earth_id: uuid.UUID
    title: str
    description: str
    category: str
    base_price_minor: int
    currency: str
    delivery_days: int
    tags: list
    status: str
    is_featured: bool
    model_config = {"from_attributes": True}


class OrderCreate(BaseModel):
    listing_id: uuid.UUID
    requirements: str | None = Field(default=None, max_length=2000)
    agreed_price_minor: int = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)


class OrderOut(BaseModel):
    id: uuid.UUID
    listing_id: uuid.UUID
    buyer_earth_id: uuid.UUID
    provider_earth_id: uuid.UUID
    agreed_price_minor: int
    currency: str
    payment_order_id: uuid.UUID | None
    status: str
    platform_fee_bps: int
    model_config = {"from_attributes": True}
