"""روتر Insurance (سند ۵: /v1/insurance/...). Dilix فقط به بیمه‌گرِ مجوزدار وصل می‌شود."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.insurance import service
from app.modules.insurance.schemas import ClaimCreate, PolicyOut, QuoteCreate

router = APIRouter(prefix="/v1/insurance", tags=["insurance"])


@router.post("/quotes", response_model=PolicyOut, status_code=201)
async def create_quote(
    data: QuoteCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PolicyOut:
    policy = await service.create_quote(db, holder_earth_id=user.earth_id, data=data)
    return PolicyOut.model_validate(policy, from_attributes=True)


@router.post("/{policy_id}/issue", response_model=PolicyOut)
async def issue(
    policy_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PolicyOut:
    policy = await service.issue(db, policy_id, user.earth_id)
    return PolicyOut.model_validate(policy, from_attributes=True)


@router.post("/{policy_id}/claims", response_model=PolicyOut)
async def claim(
    policy_id: uuid.UUID,
    data: ClaimCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PolicyOut:
    policy = await service.claim(db, policy_id, user.earth_id, data)
    return PolicyOut.model_validate(policy, from_attributes=True)
