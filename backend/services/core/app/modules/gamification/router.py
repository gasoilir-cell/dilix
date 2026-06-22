"""روتر Gamification — /v1/gamification/..."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.gamification import service
from app.modules.gamification.schemas import BadgeOut, PointsOut

router = APIRouter(prefix="/v1/gamification", tags=["gamification"])


@router.get("/points", response_model=PointsOut)
async def balance(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PointsOut:
    b = await service.get_balance(db, user.earth_id)
    return PointsOut(balance=b)


@router.get("/badges", response_model=list[BadgeOut])
async def badges(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[BadgeOut]:
    items = await service.list_badges(db, user.earth_id)
    return [BadgeOut.model_validate(b, from_attributes=True) for b in items]
