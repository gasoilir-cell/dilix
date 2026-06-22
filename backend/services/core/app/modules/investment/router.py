"""روتر Investment — /v1/investment/... (ADR-09: فقط صندوقِ مجاز)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.investment import service
from app.modules.investment.schemas import BuyRequest, NavOut, PositionOut, SellRequest

router = APIRouter(prefix="/v1/investment", tags=["investment"])


@router.get("/nav", response_model=NavOut)
async def get_nav(
    fund_code: str = Query(...),
    provider_code: str = Query(default="sandbox_fund"),
    user: CurrentUser = Depends(get_current_user),
) -> NavOut:
    nav = await service.get_nav(provider_code, fund_code)
    return NavOut(fund_code=fund_code, nav_minor=nav)


@router.post("/buy", response_model=PositionOut, status_code=201)
async def buy(
    data: BuyRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PositionOut:
    pos = await service.buy(db, earth_id=user.earth_id, data=data)
    return PositionOut.model_validate(pos, from_attributes=True)


@router.post("/sell", response_model=PositionOut)
async def sell(
    data: SellRequest,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PositionOut:
    pos = await service.sell(db, earth_id=user.earth_id, data=data)
    return PositionOut.model_validate(pos, from_attributes=True)


@router.get("/positions", response_model=list[PositionOut])
async def my_positions(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PositionOut]:
    positions = await service.my_positions(db, user.earth_id)
    return [PositionOut.model_validate(p, from_attributes=True) for p in positions]
