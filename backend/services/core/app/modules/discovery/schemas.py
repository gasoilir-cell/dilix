"""اسکیماهای Discovery."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class NearbyPerson(BaseModel):
    """نتیجه‌ی کشف — مختصات در سطحِ geo_precision هدف (نه دقیق)."""

    earth_id: uuid.UUID
    entity_type: str
    display_name: str
    avatar_url: str | None = None
    lat: float
    lon: float
    geo_precision: str
    # فیلدهای زیر فقط وقتی کاربرِ هدف آن‌ها را در visible_fields گذاشته باشد پر می‌شوند
    gender: str | None = None
    age_range: str | None = None
    marital_status: str | None = None
    profession: str | None = None
    interests: list[str] | None = None
    languages: list[str] | None = None


class ContactRequestCreate(BaseModel):
    message: str | None = Field(default=None, max_length=500)


class ContactRequestOut(BaseModel):
    id: uuid.UUID
    requester_earth_id: uuid.UUID
    target_earth_id: uuid.UUID
    message: str | None
    status: str
    model_config = {"from_attributes": True}
