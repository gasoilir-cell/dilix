"""روتر KYC — /v1/kyc/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.kyc import service
from app.modules.kyc.schemas import KycRequestCreate, KycRequestOut, KycReview

router = APIRouter(prefix="/v1/kyc", tags=["kyc"])


@router.post("/requests", response_model=KycRequestOut, status_code=201)
async def submit(
    data: KycRequestCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> KycRequestOut:
    req = await service.submit(db, subject_earth_id=user.earth_id, data=data)
    return KycRequestOut.model_validate(req, from_attributes=True)


@router.get("/requests", response_model=list[KycRequestOut])
async def my_requests(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[KycRequestOut]:
    reqs = await service.my_requests(db, user.earth_id)
    return [KycRequestOut.model_validate(r, from_attributes=True) for r in reqs]


# endpoint بررسیِ ادمین (RBAC باید سمتِ middleware/policy چک شود)
@router.post("/requests/{request_id}/review", response_model=KycRequestOut)
async def review(
    request_id: uuid.UUID,
    data: KycReview,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> KycRequestOut:
    req = await service.review(
        db, request_id=request_id, reviewer_earth_id=user.earth_id, data=data
    )
    return KycRequestOut.model_validate(req, from_attributes=True)
