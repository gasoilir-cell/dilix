"""
Dilix — Notifications Router
GET  /api/v1/notifications        لیست اعلان‌ها (آخرین ۵۰)
POST /api/v1/notifications/read   علامت‌گذاری همه به‌عنوان خوانده‌شده
POST /api/v1/notifications/{id}/read  علامت‌گذاری یک اعلان
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Text, select, update
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/notifications", tags=["Notifications"])


def _now():
    return datetime.now(timezone.utc)


class Notification(Base):
    __tablename__ = "notifications"
    id          = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id     = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    type        = Column(String(50), nullable=False, default="info")   # info/success/warning/error
    title       = Column(String(200), nullable=False)
    body        = Column(Text, nullable=True)
    is_read     = Column(Boolean, nullable=False, default=False)
    action_url  = Column(String(500), nullable=True)
    created_at  = Column(DateTime(timezone=True), nullable=False, default=_now)


# ─── GET /notifications ──────────────────────────────────────────────────────
@router.get("")
async def list_notifications(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = await db.execute(
        select(Notification)
        .where(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
    )
    items = q.scalars().all()
    unread = sum(1 for n in items if not n.is_read)

    return {
        "unread": unread,
        "items": [
            {
                "id": str(n.id),
                "type": n.type,
                "title": n.title,
                "body": n.body,
                "is_read": n.is_read,
                "action_url": n.action_url,
                "created_at": n.created_at.isoformat(),
            }
            for n in items
        ],
    }


# ─── POST /notifications/read-all ───────────────────────────────────────────
@router.post("/read-all")
async def mark_all_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(Notification)
        .where(Notification.user_id == current_user.id, Notification.is_read == False)
        .values(is_read=True)
    )
    await db.commit()
    return {"ok": True}


# ─── POST /notifications/{id}/read ──────────────────────────────────────────
@router.post("/{notif_id}/read")
async def mark_one_read(
    notif_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        nid = _uuid.UUID(notif_id)
    except ValueError:
        return {"ok": False}

    await db.execute(
        update(Notification)
        .where(Notification.id == nid, Notification.user_id == current_user.id)
        .values(is_read=True)
    )
    await db.commit()
    return {"ok": True}
