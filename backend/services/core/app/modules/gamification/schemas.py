from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel


class PointsOut(BaseModel):
    balance: int


class BadgeOut(BaseModel):
    id: uuid.UUID
    badge_code: str
    description: str | None
    awarded_at: datetime
    model_config = {"from_attributes": True}
