"""اسکیماهای Pydantic ماژول استیکر."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class PackCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=300)
    is_public: bool = False


class PackUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=300)
    is_public: bool | None = None


class StickerCreate(BaseModel):
    media_url: str = Field(..., min_length=1, max_length=500)
    media_type: str = Field(default="image", max_length=32)
    emoji_tag: str | None = Field(default=None, max_length=32)
    title: str | None = Field(default=None, max_length=120)


class StickerOut(BaseModel):
    id: uuid.UUID
    pack_id: uuid.UUID
    media_url: str
    media_type: str
    emoji_tag: str | None = None
    title: str | None = None
    is_starred: bool = False
    created_at: datetime


class PackOut(BaseModel):
    id: uuid.UUID
    owner_earth_id: uuid.UUID
    title: str
    description: str | None = None
    cover_url: str | None = None
    is_public: bool
    is_animated: bool
    is_mine: bool
    is_installed: bool
    install_count: int
    sticker_count: int
    created_at: datetime


class PackDetailOut(PackOut):
    stickers: list[StickerOut] = []
