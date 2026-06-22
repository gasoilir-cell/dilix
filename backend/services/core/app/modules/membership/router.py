"""روتر Membership — /v1/membership/..."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.membership import service
from app.modules.membership.schemas import MembershipOut, UpgradeRequest

router = APIRouter(prefix="/v1/membership", tags=["membership"])


@router.get("", response_model=MembershipOut)
async def get_membership(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> MembershipOut:
    sub = await service.get(db, user.earth_id)
    return MembershipOut.model_validate(sub, from_attributes=True)


@router.post("/upgrade", response_model=MembershipOut)
async def upgrade(
    data: UpgradeRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> MembershipOut:
    sub = await service.upgrade(db, user.earth_id, plan=data.plan, months=data.months)
    return MembershipOut.model_validate(sub, from_attributes=True)


@router.post("/cancel", response_model=MembershipOut)
async def cancel(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> MembershipOut:
    sub = await service.cancel(db, user.earth_id)
    return MembershipOut.model_validate(sub, from_attributes=True)
