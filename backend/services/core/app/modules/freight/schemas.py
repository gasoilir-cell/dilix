from __future__ import annotations
import uuid
from pydantic import BaseModel, Field


class CargoPostCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    origin: str = Field(min_length=1, max_length=120)
    destination: str = Field(min_length=1, max_length=120)
    weight_grams: int = Field(gt=0)
    budget_minor: int | None = Field(default=None, gt=0)
    currency: str = Field(default="IRR", min_length=3, max_length=3)
    meta: dict = Field(default_factory=dict)


class FreightBidCreate(BaseModel):
    price_minor: int = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    note: str | None = Field(default=None, max_length=500)


class CargoPostOut(BaseModel):
    id: uuid.UUID
    owner_earth_id: uuid.UUID
    title: str
    origin: str
    destination: str
    weight_grams: int
    budget_minor: int | None
    currency: str
    status: str
    accepted_bid_id: uuid.UUID | None
    payment_order_id: uuid.UUID | None
    shipment_id: uuid.UUID | None
    model_config = {"from_attributes": True}


class FreightBidOut(BaseModel):
    id: uuid.UUID
    cargo_post_id: uuid.UUID
    driver_earth_id: uuid.UUID
    price_minor: int
    currency: str
    note: str | None
    status: str
    model_config = {"from_attributes": True}


class LocationUpdate(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    speed_kmh: float | None = Field(default=None, ge=0)


class LocationOut(BaseModel):
    cargo_post_id: uuid.UUID
    driver_earth_id: uuid.UUID
    latitude: float
    longitude: float
    accuracy_m: float | None
    speed_kmh: float | None
    recorded_at: str
    model_config = {"from_attributes": True}
