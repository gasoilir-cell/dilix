"""Schemaهای ورودی/خروجی Identity (Pydantic) — مرز API (سند ۵)."""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from dilix_shared.earth_id import EntityType


class ProfileOut(BaseModel):
    display_name: str
    gender: str | None = None
    marital_status: str | None = None
    languages: list[str] = []
    interests: list[str] = []
    bio: str | None = None
    avatar_url: str | None = None


class IdentityOut(BaseModel):
    earth_id: uuid.UUID
    entity_type: EntityType
    status: str
    kyc_level: int
    home_region: str
    created_at: datetime
    profile: ProfileOut | None = None


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    gender: str | None = None
    marital_status: str | None = None
    languages: list[str] | None = None
    interests: list[str] | None = None
    bio: str | None = Field(default=None, max_length=500)
    avatar_url: str | None = Field(default=None, max_length=512)


class VisibilityUpdate(BaseModel):
    """تنظیم opt-in نقشه (ADR-06)."""

    discoverable: bool
    audience: Literal["public", "verified", "connections"] = "connections"
    geo_precision: Literal["exact", "city", "region"] = "region"
    visible_fields: list[
        Literal["gender", "age_range", "marital_status", "profession", "interests"]
    ] = []


class RoleChange(BaseModel):
    """درخواستِ سوییچِ نقش. فقط نقش‌های خودسرویس در service پذیرفته می‌شوند."""

    entity_type: EntityType


class RoleOption(BaseModel):
    """یک نقشِ قابلِ انتخاب در کاتالوگِ سوییچرِ نقش."""

    entity_type: EntityType
    label: str
    description: str
    self_service: bool = True
