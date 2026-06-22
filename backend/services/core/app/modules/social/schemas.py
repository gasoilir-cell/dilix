from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class PostCreate(BaseModel):
    post_type: str = Field(default="text", pattern="^(text|image|video|story|reel)$")
    content: str | None = Field(default=None, max_length=5000)
    media: list[dict] = Field(default_factory=list)
    visibility: str = Field(default="public", pattern="^(public|connections|private)$")


class CommentCreate(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    parent_id: uuid.UUID | None = None


class ReactionCreate(BaseModel):
    reaction: str = Field(min_length=1, max_length=32)


class PostOut(BaseModel):
    id: uuid.UUID
    author_earth_id: uuid.UUID
    post_type: str
    content: str | None
    media: list
    visibility: str
    reaction_counts: dict
    comment_count: int
    created_at: datetime
    model_config = {"from_attributes": True}


class CommentOut(BaseModel):
    id: uuid.UUID
    post_id: uuid.UUID
    author_earth_id: uuid.UUID
    parent_id: uuid.UUID | None
    content: str
    created_at: datetime
    model_config = {"from_attributes": True}
