"""ارکستراسیونِ پرداخت — Saga سبکِ escrow (ADR-07).

Dilix وجه را نگه نمی‌دارد: adapterِ بانک امانت می‌سازد و Dilix فقط حالت و
external_ref را ثبت و رویداد منتشر می‌کند (از طریقِ Outbox). هر گذارِ حالت با
ماشینِ حالتِ خالص اعتبارسنجی می‌شود.
"""
from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.adapter import AdapterError
from dilix_shared.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ProviderError,
)
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.payments.adapters import payment_registry
from app.modules.payments.models import (
    STATUS_CAPTURED,
    STATUS_ESCROWED,
    STATUS_FAILED,
    STATUS_REFUNDED,
    PaymentOrder,
)
from app.modules.payments.ports import EscrowRequest
from app.modules.payments.schemas import EscrowCreate
from app.modules.payments.state import can_transition


def _adapter_error_to_domain(exc: AdapterError) -> ProviderError:
    return ProviderError(exc.detail)


async def _set_status(
    db: AsyncSession, order: PaymentOrder, target: str, event_name: str
) -> None:
    if not can_transition(order.status, target):
        raise ConflictError(f"گذارِ نامعتبر: {order.status} → {target}")
    order.status = target
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name=event_name,
            payload={
                "order_id": str(order.id),
                "status": target,
                "external_ref": order.external_ref,
            },
        ),
    )


async def create_escrow(
    db: AsyncSession, *, payer_earth_id: uuid.UUID, data: EscrowCreate
) -> PaymentOrder:
    """ساختِ سفارش + ایجادِ امانت نزدِ ارائه‌دهنده. در شکست → failed."""
    order = PaymentOrder(
        payer_earth_id=payer_earth_id,
        payee_earth_id=data.payee_earth_id,
        amount_minor=data.amount_minor,
        currency=data.currency.upper(),
        provider_code=data.provider_code,
    )
    db.add(order)
    await db.flush()

    adapter = payment_registry.get(data.provider_code)
    try:
        result = await adapter.create_escrow(
            EscrowRequest(
                order_ref=str(order.id),
                amount_minor=order.amount_minor,
                currency=order.currency,
                payer_ref=str(payer_earth_id),
                payee_ref=str(data.payee_earth_id),
            )
        )
    except AdapterError as exc:
        await _set_status(db, order, STATUS_FAILED, "payments.PaymentFailed")
        raise _adapter_error_to_domain(exc) from exc

    order.external_ref = result.external_ref
    await _set_status(db, order, STATUS_ESCROWED, "payments.EscrowHeld")
    return order


async def _load_owned(
    db: AsyncSession, order_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> PaymentOrder:
    order = await db.get(PaymentOrder, order_id)
    if order is None:
        raise NotFoundError("سفارشِ پرداخت یافت نشد.")
    # فقط پرداخت‌کننده می‌تواند release/refund را آغاز کند (جلوگیری از IDOR).
    if order.payer_earth_id != actor_earth_id:
        raise ForbiddenError("اجازه‌ی این عملیات را ندارید.")
    return order


async def capture(
    db: AsyncSession, order_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> PaymentOrder:
    order = await _load_owned(db, order_id, actor_earth_id)
    adapter = payment_registry.get(order.provider_code)
    try:
        await adapter.capture(order.external_ref or "")
    except AdapterError as exc:
        raise _adapter_error_to_domain(exc) from exc
    await _set_status(db, order, STATUS_CAPTURED, "payments.EscrowCaptured")
    return order


async def refund(
    db: AsyncSession, order_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> PaymentOrder:
    order = await _load_owned(db, order_id, actor_earth_id)
    adapter = payment_registry.get(order.provider_code)
    try:
        await adapter.refund(order.external_ref or "")
    except AdapterError as exc:
        raise _adapter_error_to_domain(exc) from exc
    await _set_status(db, order, STATUS_REFUNDED, "payments.EscrowRefunded")
    return order
