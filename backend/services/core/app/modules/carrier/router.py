"""روتر Carrier (سند ۵: /v1/carrier/...). Dilix فقط به متصدیِ مجوزدار وصل می‌شود."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.carrier import service
from app.modules.carrier.schemas import ShipmentCreate, ShipmentOut

router = APIRouter(prefix="/v1/carrier", tags=["carrier"])


@router.post("/shipments", response_model=ShipmentOut, status_code=201)
async def create_shipment(
    data: ShipmentCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShipmentOut:
    shipment = await service.create_shipment(db, shipper_earth_id=user.earth_id, data=data)
    return ShipmentOut.model_validate(shipment, from_attributes=True)


@router.get("/shipments/{shipment_id}/track", response_model=ShipmentOut)
async def track(
    shipment_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShipmentOut:
    shipment = await service.track(db, shipment_id, user.earth_id)
    return ShipmentOut.model_validate(shipment, from_attributes=True)
