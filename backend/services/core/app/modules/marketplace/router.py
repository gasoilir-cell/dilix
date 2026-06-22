"""روتر Marketplace (سند ۵: /v1/marketplace/...)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import get_current_earth_id
from app.modules.marketplace import service
from app.modules.marketplace.schemas import (
    ListingCreate, ListingOut, OrderCreate, OrderOut,
)

router = APIRouter(prefix="/v1/marketplace", tags=["marketplace"])


@router.post("/listings", response_model=ListingOut, status_code=201)
async def create_listing(
    data: ListingCreate,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> ListingOut:
    listing = await service.create_listing(db, earth_id, data)
    return ListingOut.model_validate(listing, from_attributes=True)


@router.get("/listings", response_model=list[ListingOut])
async def search_listings(
    category: str | None = Query(default=None),
    keyword: str | None = Query(default=None, max_length=100),
    db: AsyncSession = Depends(get_session),
    _: uuid.UUID = Depends(get_current_earth_id),
) -> list[ListingOut]:
    listings = await service.search_listings(db, category, keyword)
    return [ListingOut.model_validate(l, from_attributes=True) for l in listings]


@router.post("/orders", response_model=OrderOut, status_code=201)
async def place_order(
    data: OrderCreate,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> OrderOut:
    order = await service.place_order(db, earth_id, data)
    return OrderOut.model_validate(order, from_attributes=True)


@router.post("/orders/{order_id}/accept", response_model=OrderOut)
async def accept_order(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> OrderOut:
    order = await service.accept_order(db, order_id, earth_id)
    return OrderOut.model_validate(order, from_attributes=True)


@router.post("/orders/{order_id}/deliver", response_model=OrderOut)
async def deliver_order(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> OrderOut:
    order = await service.deliver_order(db, order_id, earth_id)
    return OrderOut.model_validate(order, from_attributes=True)


@router.post("/orders/{order_id}/complete", response_model=OrderOut)
async def complete_order(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> OrderOut:
    order = await service.complete_order(db, order_id, earth_id)
    return OrderOut.model_validate(order, from_attributes=True)
