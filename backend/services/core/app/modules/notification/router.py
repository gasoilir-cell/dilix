"""روتر Notification — /v1/notifications/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.notification import service
from app.modules.notification.schemas import NotificationOut

router = APIRouter(prefix="/v1/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationOut])
async def inbox(
    unread_only: bool = Query(default=False),
    limit: int = Query(default=50, le=200),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[NotificationOut]:
    items = await service.list_inbox(db, user.earth_id, unread_only=unread_only, limit=limit)
    return [NotificationOut.model_validate(n, from_attributes=True) for n in items]


@router.post("/{notification_id}/read", status_code=204)
async def mark_read(
    notification_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await service.mark_read(db, notification_id, user.earth_id)
