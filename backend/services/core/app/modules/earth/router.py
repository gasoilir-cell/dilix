"""روتر Earth/Location — /v1/earth/..."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.earth import service
from app.modules.earth.schemas import LocationOut, LocationUpdate, PoiCreate, PoiOut

router = APIRouter(prefix="/v1/earth", tags=["earth"])


@router.put("/location", response_model=LocationOut)
async def update_location(
    data: LocationUpdate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> LocationOut:
    pin = await service.update_location(db, earth_id=user.earth_id, data=data)
    return LocationOut.model_validate(pin, from_attributes=True)


@router.get("/location", response_model=LocationOut)
async def my_location(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> LocationOut:
    pin = await service.get_location(db, user.earth_id)
    return LocationOut.model_validate(pin, from_attributes=True)


@router.get("/pois", response_model=list[PoiOut])
async def nearby_pois(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(default=10.0, le=100.0),
    category: str | None = Query(default=None),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PoiOut]:
    pois = await service.nearby_pois(db, lat, lon, radius_km, category)
    return [PoiOut.model_validate(p, from_attributes=True) for p in pois]


@router.post("/pois", response_model=PoiOut, status_code=201)
async def create_poi(
    data: PoiCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PoiOut:
    poi = await service.create_poi(db, owner_earth_id=user.earth_id, data=data)
    return PoiOut.model_validate(poi, from_attributes=True)
