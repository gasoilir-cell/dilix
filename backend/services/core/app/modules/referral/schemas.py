from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel


class ReferralRegister(BaseModel):
    referrer_earth_id: uuid.UUID


class ReferralOut(BaseModel):
    id: uuid.UUID
    referrer_earth_id: uuid.UUID
    referred_earth_id: uuid.UUID
    level: int
    status: str
    reward_minor: int | None
    currency: str
    rewarded_at: datetime | None
    model_config = {"from_attributes": True}
