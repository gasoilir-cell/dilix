"""روتر Telecom — /v1/telecom/..."""
from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.telecom import service
from app.modules.telecom.schemas import EsimCreate, EsimOut, TopUpCreate, TopUpOut

router = APIRouter(prefix="/v1/telecom", tags=["telecom"])


@router.post("/top-up", response_model=TopUpOut, status_code=201)
async def top_up(
    data: TopUpCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> TopUpOut:
    order = await service.top_up(db, earth_id=user.earth_id, data=data)
    return TopUpOut.model_validate(order, from_attributes=True)


@router.post("/esim/activate", response_model=EsimOut, status_code=201)
async def activate_esim(
    data: EsimCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> EsimOut:
    profile = await service.activate_esim(db, earth_id=user.earth_id, data=data)
    return EsimOut.model_validate(profile, from_attributes=True)
