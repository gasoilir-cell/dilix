"""روتر Freight — /v1/freight/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.freight import service
from app.modules.freight.schemas import (
    CargoPostCreate, CargoPostOut, FreightBidCreate, FreightBidOut,
    LocationUpdate, LocationOut,
)

router = APIRouter(prefix="/v1/freight", tags=["freight"])


@router.post("/cargo", response_model=CargoPostOut, status_code=201)
async def post_cargo(
    data: CargoPostCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CargoPostOut:
    cargo = await service.post_cargo(db, owner_earth_id=user.earth_id, data=data)
    return CargoPostOut.model_validate(cargo, from_attributes=True)


@router.get("/cargo", response_model=list[CargoPostOut])
async def list_open(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[CargoPostOut]:
    return [CargoPostOut.model_validate(c, from_attributes=True) for c in await service.list_open(db)]


@router.get("/cargo/{cargo_id}/bids", response_model=list[FreightBidOut])
async def list_bids(
    cargo_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[FreightBidOut]:
    return [FreightBidOut.model_validate(b, from_attributes=True) for b in await service.list_bids(db, cargo_id)]


@router.post("/cargo/{cargo_id}/bids", response_model=FreightBidOut, status_code=201)
async def place_bid(
    cargo_id: uuid.UUID,
    data: FreightBidCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> FreightBidOut:
    bid = await service.place_bid(db, cargo_id=cargo_id, driver_earth_id=user.earth_id, data=data)
    return FreightBidOut.model_validate(bid, from_attributes=True)


@router.post("/bids/{bid_id}/accept", response_model=CargoPostOut)
async def accept_bid(
    bid_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CargoPostOut:
    cargo = await service.accept_bid(db, bid_id=bid_id, owner_earth_id=user.earth_id)
    return CargoPostOut.model_validate(cargo, from_attributes=True)


@router.post("/cargo/{cargo_id}/pickup", response_model=CargoPostOut)
async def confirm_pickup(
    cargo_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CargoPostOut:
    cargo = await service.confirm_pickup(db, cargo_id, user.earth_id)
    return CargoPostOut.model_validate(cargo, from_attributes=True)


@router.post("/cargo/{cargo_id}/deliver", response_model=CargoPostOut)
async def confirm_delivery(
    cargo_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CargoPostOut:
    cargo = await service.confirm_delivery(db, cargo_id, user.earth_id)
    return CargoPostOut.model_validate(cargo, from_attributes=True)


@router.post("/cargo/{cargo_id}/settle", response_model=CargoPostOut)
async def release_escrow(
    cargo_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CargoPostOut:
    cargo = await service.release_escrow(db, cargo_id, user.earth_id)
    return CargoPostOut.model_validate(cargo, from_attributes=True)


@router.post("/cargo/{cargo_id}/location", response_model=LocationOut, status_code=201)
async def post_location(
    cargo_id: uuid.UUID,
    data: LocationUpdate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> LocationOut:
    """راننده موقعیت GPS را ارسال می‌کند."""
    loc = await service.update_location(db, cargo_id, user.earth_id, data)
    return LocationOut(
        cargo_post_id=loc.cargo_post_id,
        driver_earth_id=loc.driver_earth_id,
        latitude=loc.latitude,
        longitude=loc.longitude,
        accuracy_m=loc.accuracy_m,
        speed_kmh=loc.speed_kmh,
        recorded_at=loc.recorded_at.isoformat(),
    )


@router.get("/cargo/{cargo_id}/location", response_model=LocationOut | None)
async def get_location(
    cargo_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> LocationOut | None:
    """آخرین موقعیت GPS بار."""
    loc = await service.get_last_location(db, cargo_id)
    if loc is None:
        return None
    return LocationOut(
        cargo_post_id=loc.cargo_post_id,
        driver_earth_id=loc.driver_earth_id,
        latitude=loc.latitude,
        longitude=loc.longitude,
        accuracy_m=loc.accuracy_m,
        speed_kmh=loc.speed_kmh,
        recorded_at=loc.recorded_at.isoformat(),
    )
