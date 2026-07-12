"""اسکیماهای Pydantic ماژول داستان."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class StoryCreate(BaseModel):
    media_url: str = Field(..., min_length=1)
    media_type: str = Field(default="image", max_length=12)
    caption: str | None = Field(default=None, max_length=500)
    audience: str = Field(default="public", max_length=16)


class StoryOut(BaseModel):
    id: uuid.UUID
    author_earth_id: uuid.UUID
    media_url: str
    media_type: str
    caption: str | None = None
    audience: str = "public"
    view_count: int = 0
    viewed_by_me: bool = False
    is_mine: bool = False
    created_at: datetime


class RingOut(BaseModel):
    author_earth_id: uuid.UUID
    story_count: int = 0
    has_unseen: bool = False
    is_me: bool = False
    latest_at: datetime


class ViewerOut(BaseModel):
    viewer_earth_id: uuid.UUID
    viewed_at: datetime


class CircleMember(BaseModel):
    earth_id: uuid.UUID


class CirclesOut(BaseModel):
    colleagues: list[CircleMember] = []
    family: list[CircleMember] = []
    friends: list[CircleMember] = []


class CircleAddIn(BaseModel):
    earth_id: uuid.UUID
