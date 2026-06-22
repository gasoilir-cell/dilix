"""Schemaهای Reputation (سند ۵)."""
from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class ReviewCreate(BaseModel):
    reviewee_earth_id: uuid.UUID
    domain: str = Field(max_length=32)
    transaction_ref: str = Field(max_length=128)
    rating: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=1000)


class ReviewOut(BaseModel):
    id: uuid.UUID
    reviewee_earth_id: uuid.UUID
    reviewer_earth_id: uuid.UUID
    domain: str
    transaction_ref: str
    rating: int
    comment: str | None
    model_config = {"from_attributes": True}


class ScoreOut(BaseModel):
    earth_id: uuid.UUID
    domain: str
    score: float  # ÷10 نمایش داده می‌شود (۰–۱۰۰)
    review_count: int
    model_config = {"from_attributes": True}
