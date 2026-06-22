"""روتر Payments (سند ۵: /v1/payments/...). مدلِ escrow؛ Dilix فقط ارکستریت می‌کند."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.payments import service
from app.modules.payments.schemas import EscrowCreate, PaymentOrderOut

router = APIRouter(prefix="/v1/payments", tags=["payments"])


@router.post("/escrow", response_model=PaymentOrderOut, status_code=201)
async def create_escrow(
    data: EscrowCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PaymentOrderOut:
    order = await service.create_escrow(db, payer_earth_id=user.earth_id, data=data)
    return PaymentOrderOut.model_validate(order, from_attributes=True)


@router.post("/{order_id}/capture", response_model=PaymentOrderOut)
async def capture(
    order_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PaymentOrderOut:
    order = await service.capture(db, order_id, user.earth_id)
    return PaymentOrderOut.model_validate(order, from_attributes=True)


@router.post("/{order_id}/refund", response_model=PaymentOrderOut)
async def refund(
    order_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PaymentOrderOut:
    order = await service.refund(db, order_id, user.earth_id)
    return PaymentOrderOut.model_validate(order, from_attributes=True)
