"""سرویس Earth — موقعیت‌یابی با fuzzing و POI (ADR-06)."""
from __future__ import annotations

import math
import random
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ForbiddenError, NotFoundError

from app.modules.earth.models import (
    PRECISION_CITY, PRECISION_DISTRICT, PRECISION_EXACT, PRECISION_REGION,
    LocationPin, PointOfInterest,
)
from app.modules.earth.schemas import LocationUpdate, PoiCreate

# میزانِ fuzzing بر حسبِ درجه برای هر سطحِ دقت
_FUZZ_DEG: dict[str, float] = {
    PRECISION_EXACT: 0.0,
    PRECISION_DISTRICT: 0.01,   # ~۱ کیلومتر
    PRECISION_CITY: 0.05,       # ~۵ کیلومتر
    PRECISION_REGION: 0.5,      # ~۵۰ کیلومتر
}


def _fuzz(lat: float, lon: float, precision: str) -> tuple[float, float]:
    deg = _FUZZ_DEG.get(precision, 0.5)
    if deg == 0:
        return lat, lon
    return (
        lat + random.uniform(-deg, deg),
        lon + random.uniform(-deg, deg),
    )


async def update_location(
    db: AsyncSession, *, earth_id: uuid.UUID, data: LocationUpdate
) -> LocationPin:
    fuzz_lat, fuzz_lon = _fuzz(data.lat, data.lon, data.geo_precision)
    pin = await db.get(LocationPin, earth_id)
    if pin is None:
        pin = LocationPin(earth_id=earth_id)
        db.add(pin)
    pin.lat = fuzz_lat
    pin.lon = fuzz_lon
    pin.geo_precision = data.geo_precision
    pin.is_visible = data.is_visible
    pin.country_code = data.country_code
    await db.flush()
    return pin


async def get_location(db: AsyncSession, earth_id: uuid.UUID) -> LocationPin:
    pin = await db.get(LocationPin, earth_id)
    if pin is None:
        raise NotFoundError("موقعیتِ کاربر ثبت نشده یا opt-in نشده.")
    return pin


async def nearby_pois(
    db: AsyncSession,
    lat: float,
    lon: float,
    radius_km: float = 10.0,
    category: str | None = None,
) -> list[PointOfInterest]:
    """جستجوی ساده بدون PostGIS — برای PostGIS واقعی باید ST_DWithin استفاده شود."""
    q = select(PointOfInterest).where(PointOfInterest.is_active.is_(True))
    if category:
        q = q.where(PointOfInterest.category == category)
    result = await db.execute(q.limit(500))
    pois = result.scalars().all()
    # فیلترِ فاصله روی پایتون (placeholder تا PostGIS فعال شود)
    deg_per_km = 1 / 111.0
    threshold = radius_km * deg_per_km
    return [
        p for p in pois
        if math.hypot(p.lat - lat, p.lon - lon) <= threshold
    ]


async def create_poi(
    db: AsyncSession, *, owner_earth_id: uuid.UUID, data: PoiCreate
) -> PointOfInterest:
    poi = PointOfInterest(
        owner_earth_id=owner_earth_id,
        name=data.name,
        category=data.category,
        lat=data.lat,
        lon=data.lon,
        country_code=data.country_code.upper(),
    )
    db.add(poi)
    await db.flush()
    return poi
