from __future__ import annotations
import uuid
from pydantic import BaseModel, Field


class KycRequestCreate(BaseModel):
    requested_level: int = Field(ge=1, le=3)
    documents: dict = Field(default_factory=dict)


class KycReview(BaseModel):
    approved: bool
    note: str | None = None


class KycRequestOut(BaseModel):
    id: uuid.UUID
    subject_earth_id: uuid.UUID
    requested_level: int
    status: str
    note: str | None
    reviewer_earth_id: uuid.UUID | None

    model_config = {"from_attributes": True}
