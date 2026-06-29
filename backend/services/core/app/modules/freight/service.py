"""ساگای Freight — ارکستراسیونِ کاملِ جریانِ بار (ADR-02 / سند ۴).

جریان:
  post_cargo → place_bid → accept_bid [→ escrow+waybill Saga] →
  confirm_pickup → confirm_delivery → release_escrow

Dilix وجه و بارنامه را نگه نمی‌دارد؛ فقط ارکستریت می‌کند.
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.carrier.schemas import ShipmentCreate
from app.modules.carrier import service as carrier_svc
from app.modules.freight.models import (
    BID_ACCEPTED, BID_PENDING, BID_REJECTED,
    CARGO_ASSIGNED, CARGO_BIDDING, CARGO_DELIVERED, CARGO_IN_TRANSIT, CARGO_OPEN, CARGO_SETTLED,
    CargoPost, FreightBid, FreightLocation,
)
from app.modules.freight.schemas import CargoPostCreate, FreightBidCreate, LocationUpdate
from app.modules.freight.state import can_transition
from app.modules.payments.schemas import EscrowCreate
from app.modules.payments import service as payment_svc


async def _set_cargo_status(
    db: AsyncSession, cargo: CargoPost, target: str, event_name: str, **extra
) -> None:
    if not can_transition(cargo.status, target):
        raise ConflictError(f"گذارِ نامعتبر: {cargo.status} → {target}")
    cargo.status = target
    await db.flush()
    payload = {"cargo_id": str(cargo.id), "status": target}
    payload.update(extra)
    await publisher.publish(db, DomainEvent(name=event_name, payload=payload))


async def post_cargo(
    db: AsyncSession, *, owner_earth_id: uuid.UUID, data: CargoPostCreate
) -> CargoPost:
    cargo = CargoPost(
        owner_earth_id=owner_earth_id,
        title=data.title,
        description=data.description,
        origin=data.origin,
        destination=data.destination,
        weight_grams=data.weight_grams,
        budget_minor=data.budget_minor,
        currency=data.currency.upper(),
        meta=data.meta,
    )
    db.add(cargo)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="freight.CargoPosted",
            payload={"cargo_id": str(cargo.id), "owner": str(owner_earth_id)},
        ),
    )
    return cargo


async def place_bid(
    db: AsyncSession, *, cargo_id: uuid.UUID, driver_earth_id: uuid.UUID, data: FreightBidCreate
) -> FreightBid:
    cargo = await db.get(CargoPost, cargo_id)
    if cargo is None:
        raise NotFoundError("بار یافت نشد.")
    if cargo.status not in (CARGO_OPEN, CARGO_BIDDING):
        raise ConflictError("این بار دیگر بیدپذیر نیست.")
    if cargo.owner_earth_id == driver_earth_id:
        raise ForbiddenError("صاحب‌بار نمی‌تواند برای بارِ خود bid بدهد.")

    bid = FreightBid(
        cargo_post_id=cargo_id,
        driver_earth_id=driver_earth_id,
        price_minor=data.price_minor,
        currency=data.currency.upper(),
        note=data.note,
    )
    db.add(bid)
    if cargo.status == CARGO_OPEN:
        await _set_cargo_status(db, cargo, CARGO_BIDDING, "freight.FirstBidReceived")
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="freight.BidPlaced",
            payload={"bid_id": str(bid.id), "cargo_id": str(cargo_id)},
        ),
    )
    return bid


async def accept_bid(
    db: AsyncSession, *, bid_id: uuid.UUID, owner_earth_id: uuid.UUID
) -> CargoPost:
    """قبولِ bid + ایجادِ escrow + صدورِ بارنامه (Saga)."""
    bid = await db.get(FreightBid, bid_id)
    if bid is None:
        raise NotFoundError("bid یافت نشد.")
    if bid.status != BID_PENDING:
        raise ConflictError("این bid قبلاً پردازش شده.")

    cargo = await db.get(CargoPost, bid.cargo_post_id)
    if cargo is None:
        raise NotFoundError("بار یافت نشد.")
    if cargo.owner_earth_id != owner_earth_id:
        raise ForbiddenError("اجازه‌ی این عملیات را ندارید.")

    # رد کردنِ بقیه‌ی bidها
    all_bids_result = await db.execute(
        select(FreightBid).where(
            FreightBid.cargo_post_id == bid.cargo_post_id,
            FreightBid.status == BID_PENDING,
            FreightBid.id != bid_id,
        )
    )
    for other in all_bids_result.scalars().all():
        other.status = BID_REJECTED

    bid.status = BID_ACCEPTED

    # --- Saga Step 1: ایجادِ escrow پرداخت ---
    payment_order = await payment_svc.create_escrow(
        db,
        payer_earth_id=owner_earth_id,
        data=EscrowCreate(
            payee_earth_id=bid.driver_earth_id,
            amount_minor=bid.price_minor,
            currency=bid.currency,
            provider_code="sandbox",
        ),
    )
    cargo.payment_order_id = payment_order.id

    # --- Saga Step 2: صدورِ بارنامه ---
    shipment = await carrier_svc.create_shipment(
        db,
        shipper_earth_id=owner_earth_id,
        data=ShipmentCreate(
            origin=cargo.origin,
            destination=cargo.destination,
            weight_grams=cargo.weight_grams,
            provider_code="sandbox",
        ),
    )
    cargo.shipment_id = shipment.id
    cargo.accepted_bid_id = bid_id

    await _set_cargo_status(
        db, cargo, CARGO_ASSIGNED, "freight.BidAccepted",
        bid_id=str(bid_id), driver_id=str(bid.driver_earth_id),
    )
    return cargo


async def confirm_pickup(
    db: AsyncSession, cargo_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> CargoPost:
    """راننده تأیید می‌کند که بار را تحویل گرفته."""
    cargo, bid = await _load_cargo_and_bid(db, cargo_id)
    if cargo.owner_earth_id != actor_earth_id and bid.driver_earth_id != actor_earth_id:
        raise ForbiddenError("فقط صاحب‌بار یا رانندهٔ تعیین‌شده می‌توانند.")
    await _set_cargo_status(db, cargo, CARGO_IN_TRANSIT, "freight.PickedUp")
    return cargo


async def confirm_delivery(
    db: AsyncSession, cargo_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> CargoPost:
    """صاحب‌بار یا راننده تأیید می‌کند که کالا تحویل داده شده."""
    cargo, bid = await _load_cargo_and_bid(db, cargo_id)
    if cargo.owner_earth_id != actor_earth_id and bid.driver_earth_id != actor_earth_id:
        raise ForbiddenError("فقط صاحب‌بار یا رانندهٔ تعیین‌شده می‌توانند.")
    await _set_cargo_status(db, cargo, CARGO_DELIVERED, "freight.Delivered")
    return cargo


async def release_escrow(
    db: AsyncSession, cargo_id: uuid.UUID, owner_earth_id: uuid.UUID
) -> CargoPost:
    """صاحب‌بار escrow را آزاد و تسویه می‌کند."""
    cargo, _ = await _load_cargo_and_bid(db, cargo_id)
    if cargo.owner_earth_id != owner_earth_id:
        raise ForbiddenError("فقط صاحب‌بار می‌تواند تسویه کند.")
    if cargo.status != CARGO_DELIVERED:
        raise ConflictError("تسویه فقط پس از تحویل ممکن است.")
    if cargo.payment_order_id:
        await payment_svc.capture(db, cargo.payment_order_id, owner_earth_id)
    await _set_cargo_status(db, cargo, CARGO_SETTLED, "freight.Settled")
    return cargo


async def list_open(db: AsyncSession) -> list[CargoPost]:
    result = await db.execute(
        select(CargoPost).where(
            CargoPost.status.in_([CARGO_OPEN, CARGO_BIDDING])
        ).order_by(CargoPost.created_at.desc()).limit(100)
    )
    return list(result.scalars().all())


async def list_bids(db: AsyncSession, cargo_id: uuid.UUID) -> list[FreightBid]:
    result = await db.execute(
        select(FreightBid).where(FreightBid.cargo_post_id == cargo_id)
        .order_by(FreightBid.created_at.asc())
    )
    return list(result.scalars().all())


async def update_location(
    db: AsyncSession,
    cargo_id: uuid.UUID,
    driver_earth_id: uuid.UUID,
    data: LocationUpdate,
) -> FreightLocation:
    """راننده موقعیت GPS خود را ارسال می‌کند."""
    cargo = await db.get(CargoPost, cargo_id)
    if cargo is None:
        raise NotFoundError("بار یافت نشد.")
    if cargo.status != CARGO_IN_TRANSIT:
        raise ConflictError("ارسال موقعیت فقط در حین حمل ممکن است.")

    loc = FreightLocation(
        cargo_post_id=cargo_id,
        driver_earth_id=driver_earth_id,
        latitude=data.latitude,
        longitude=data.longitude,
        accuracy_m=data.accuracy_m,
        speed_kmh=data.speed_kmh,
    )
    db.add(loc)
    await db.flush()

    # رویداد realtime (دریافت‌کنندگان از WebSocket manager می‌گیرند)
    await publisher.publish(
        db,
        DomainEvent(
            name="freight.LocationUpdated",
            payload={
                "cargo_id": str(cargo_id),
                "lat": data.latitude,
                "lng": data.longitude,
                "speed_kmh": data.speed_kmh,
            },
        ),
    )
    return loc


async def get_last_location(
    db: AsyncSession, cargo_id: uuid.UUID
) -> FreightLocation | None:
    """آخرین موقعیت GPS بار را برمی‌گرداند."""
    result = await db.execute(
        select(FreightLocation)
        .where(FreightLocation.cargo_post_id == cargo_id)
        .order_by(FreightLocation.recorded_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def _load_cargo_and_bid(
    db: AsyncSession, cargo_id: uuid.UUID
) -> tuple[CargoPost, FreightBid]:
    cargo = await db.get(CargoPost, cargo_id)
    if cargo is None:
        raise NotFoundError("بار یافت نشد.")
    if not cargo.accepted_bid_id:
        raise ConflictError("بارِ هنوز assign‌نشده.")
    bid = await db.get(FreightBid, cargo.accepted_bid_id)
    if bid is None:
        raise NotFoundError("bid یافت نشد.")
    return cargo, bid
