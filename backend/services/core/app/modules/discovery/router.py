"""روتر Discovery — /v1/discovery/... (سند ۵ §۴)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import DilixError

from app.core.database import get_session
from app.modules.auth.deps import get_current_earth_id
from app.modules.discovery import service
from app.modules.discovery.schemas import (
    ContactRequestCreate,
    ContactRequestOut,
    NearbyPerson,
)

router = APIRouter(prefix="/v1/discovery", tags=["discovery"])


def _parse_bbox(bbox: str | None) -> tuple[float | None, float | None, float | None, float | None]:
    """bbox = "min_lat,min_lon,max_lat,max_lon"."""
    if not bbox:
        return None, None, None, None
    try:
        min_lat, min_lon, max_lat, max_lon = (float(x) for x in bbox.split(","))
    except (ValueError, TypeError) as exc:
        raise _BadBbox() from exc
    return min_lat, max_lat, min_lon, max_lon


class _BadBbox(DilixError):
    error_type = "invalid_bbox"

    def __init__(self) -> None:
        super().__init__("قالبِ bbox نامعتبر است: min_lat,min_lon,max_lat,max_lon")


@router.get("/nearby", response_model=list[NearbyPerson])
async def nearby(
    bbox: str | None = Query(default=None, description="min_lat,min_lon,max_lat,max_lon"),
    entity_type: str | None = Query(default=None),
    gender: str | None = Query(default=None),
    age_range: str | None = Query(default=None, description="مثال: 25-34"),
    profession: str | None = Query(default=None),
    business_category: str | None = Query(default=None),
    language: str | None = Query(default=None),
    marital_status: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=200),
    db: AsyncSession = Depends(get_session),
    requester_earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> list[NearbyPerson]:
    """کشفِ افراد/کسب‌وکارِ قابلِ‌کشف در محدوده‌ی نقشه؛ مختصاتِ دقیق برنمی‌گردد."""
    min_lat, max_lat, min_lon, max_lon = _parse_bbox(bbox)
    return await service.search_nearby(
        db,
        requester_earth_id=requester_earth_id,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
        entity_type=entity_type,
        gender=gender,
        age_range=age_range,
        profession=profession,
        business_category=business_category,
        language=language,
        marital_status=marital_status,
        limit=limit,
    )


@router.post(
    "/{earth_id}/contact-request",
    response_model=ContactRequestOut,
    status_code=201,
)
async def contact_request(
    earth_id: uuid.UUID,
    data: ContactRequestCreate,
    db: AsyncSession = Depends(get_session),
    requester_earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> ContactRequestOut:
    """درخواستِ شروعِ گفتگو با فردِ کشف‌شده."""
    req = await service.create_contact_request(
        db,
        requester_earth_id=requester_earth_id,
        target_earth_id=earth_id,
        message=data.message,
    )
    return ContactRequestOut.model_validate(req, from_attributes=True)
