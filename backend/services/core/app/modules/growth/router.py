"""روتر Growth — /v1/growth/... (سند ۵ §۸)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import get_current_earth_id
from app.modules.growth import service
from app.modules.growth.schemas import (
    ReferralLinkOut,
    RevenueShareOut,
    RewardWalletOut,
)

router = APIRouter(prefix="/v1/growth", tags=["growth"])


@router.get("/referrals/link", response_model=ReferralLinkOut)
async def my_referral_link(
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> ReferralLinkOut:
    """لینکِ دعوتِ من."""
    return await service.referral_link(db, earth_id)


@router.get("/rewards", response_model=RewardWalletOut)
async def my_rewards(
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> RewardWalletOut:
    """کیفِ پاداش — فقط پاداش‌هایِ gated به reward_event واقعی (ADR-08)."""
    return await service.reward_wallet(db, earth_id)


@router.get("/revenue-share", response_model=RevenueShareOut)
async def my_revenue_share(
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> RevenueShareOut:
    """سهم از درآمدِ کارمزدِ پلتفرم (Vanguard-style)."""
    return await service.revenue_share(db, earth_id)
