"""ارکستراسیونِ حمل‌ونقل — create_waybill → track (ADR-02).

Dilix متصدیِ حمل نیست: adapterِ متصدی بارنامه صادر می‌کند و Dilix حالت و
waybill_no را ثبت و رویداد منتشر می‌کند (از طریقِ Outbox). track وضعیتِ زنده را
از متصدی می‌گیرد و در صورتِ معتبربودنِ گذار، حالتِ محلی را همگام می‌کند.
"""
from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.adapter import AdapterError
from dilix_shared.errors import ForbiddenError, NotFoundError, ProviderError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.carrier.adapters import carrier_registry
from app.modules.carrier.models import STATUS_DISPATCHED, Shipment
from app.modules.carrier.ports import WaybillRequest
from app.modules.carrier.schemas import ShipmentCreate
from app.modules.carrier.state import CARRIER_STATUS_MAP, can_transition


def _to_domain(exc: AdapterError) -> ProviderError:
    return ProviderError(exc.detail)


async def create_shipment(
    db: AsyncSession, *, shipper_earth_id: uuid.UUID, data: ShipmentCreate
) -> Shipment:
    shipment = Shipment(
        shipper_earth_id=shipper_earth_id,
        provider_code=data.provider_code,
        origin=data.origin,
        destination=data.destination,
        weight_grams=data.weight_grams,
    )
    db.add(shipment)
    await db.flush()

    adapter = carrier_registry.get(data.provider_code)
    try:
        result = await adapter.create_waybill(
            WaybillRequest(
                shipment_ref=str(shipment.id),
                shipper_ref=str(shipper_earth_id),
                origin=data.origin,
                destination=data.destination,
                weight_grams=data.weight_grams,
            )
        )
    except AdapterError as exc:
        raise _to_domain(exc) from exc

    shipment.waybill_no = result.waybill_no
    shipment.status = STATUS_DISPATCHED
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="carrier.WaybillCreated",
            payload={
                "shipment_id": str(shipment.id),
                "waybill_no": shipment.waybill_no,
                "status": shipment.status,
            },
        ),
    )
    return shipment


async def track(
    db: AsyncSession, shipment_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> Shipment:
    shipment = await db.get(Shipment, shipment_id)
    if shipment is None:
        raise NotFoundError("محموله یافت نشد.")
    if shipment.shipper_earth_id != actor_earth_id:
        raise ForbiddenError("اجازه‌ی این عملیات را ندارید.")

    adapter = carrier_registry.get(shipment.provider_code)
    try:
        info = await adapter.track(shipment.waybill_no or "")
    except AdapterError as exc:
        raise _to_domain(exc) from exc

    shipment.last_location = info.last_location
    target = CARRIER_STATUS_MAP.get(info.status)
    # فقط اگر متصدی وضعیتِ جلوتری گزارش کرد و گذار معتبر بود، همگام کن.
    if target and target != shipment.status and can_transition(shipment.status, target):
        shipment.status = target
        await db.flush()
        await publisher.publish(
            db,
            DomainEvent(
                name="carrier.ShipmentStatusChanged",
                payload={"shipment_id": str(shipment.id), "status": target},
            ),
        )
    else:
        await db.flush()
    return shipment
