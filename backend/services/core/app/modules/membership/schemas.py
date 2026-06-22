from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class UpgradeRequest(BaseModel):
    plan: str = Field(pattern="^(free|standard|premium)$")
    months: int = Field(default=1, ge=1, le=12)


class MembershipOut(BaseModel):
    id: uuid.UUID
    earth_id: uuid.UUID
    plan: str
    status: str
    cashback_bps: int
    expires_at: datetime | None
    model_config = {"from_attributes": True}
