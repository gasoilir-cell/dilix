"""روتر Referral — /v1/referral/..."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.referral import service
from app.modules.referral.schemas import ReferralOut, ReferralRegister

router = APIRouter(prefix="/v1/referral", tags=["referral"])


@router.post("/register", response_model=list[ReferralOut], status_code=201)
async def register(
    data: ReferralRegister,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ReferralOut]:
    referrals = await service.register(
        db,
        referred_earth_id=user.earth_id,
        referrer_earth_id=data.referrer_earth_id,
    )
    return [ReferralOut.model_validate(r, from_attributes=True) for r in referrals]
