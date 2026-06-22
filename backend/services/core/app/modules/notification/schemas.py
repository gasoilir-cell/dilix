from __future__ import annotations
import uuid
from datetime import datetime
from pydantic import BaseModel


class NotificationOut(BaseModel):
    id: uuid.UUID
    recipient_earth_id: uuid.UUID
    channel: str
    title: str
    body: str
    status: str
    read: bool
    created_at: datetime
    model_config = {"from_attributes": True}
