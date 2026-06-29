"""سرویس Marketplace — بازارگاه خدمات فریلنسری (Milestone 3).

جریان:
  ارائه‌دهنده → ثبت سرویس → مشتری سفارش می‌دهد → escrow بسته می‌شود →
  ارائه‌دهنده تحویل می‌دهد → مشتری تأیید می‌کند → escrow آزاد (کارمزد Dilix کسر).
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.marketplace.models import (
    ORDER_ACCEPTED, ORDER_COMPLETED,
    ORDER_DELIVERED, ORDER_IN_PROGRESS, ORDER_PENDING,
    SERVICE_ACTIVE, ServiceListing, ServiceOrder,
)
from app.modules.marketplace.schemas import ListingCreate, OrderCreate
from app.modules.payments.schemas import EscrowCreate
from app.modules.payments import service as payment_svc

PLATFORM_FEE_BPS = 500  # ۵٪


async def create_listing(
    db: AsyncSession, provider_earth_id: uuid.UUID, data: ListingCreate
) -> ServiceListing:
    listing = ServiceListing(
        provider_earth_id=provider_earth_id,
        title=data.title,
        description=data.description,
        category=data.category,
        base_price_minor=data.base_price_minor,
        currency=data.currency.upper(),
        delivery_days=data.delivery_days,
        tags=data.tags,
        media_refs=data.media_refs,
    )
    db.add(listing)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="marketplace.ListingCreated",
            payload={"listing_id": str(listing.id), "provider": str(provider_earth_id)},
        ),
    )
    return listing


async def search_listings(
    db: AsyncSession, category: str | None = None, keyword: str | None = None
) -> list[ServiceListing]:
    q = select(ServiceListing).where(ServiceListing.status == SERVICE_ACTIVE)
    if category:
        q = q.where(ServiceListing.category == category)
    result = await db.execute(q.order_by(ServiceListing.is_featured.desc(), ServiceListing.created_at.desc()).limit(50))
    listings = list(result.scalars().all())
    if keyword:
        kw = keyword.lower()
        listings = [
            item for item in listings
            if kw in item.title.lower() or kw in item.description.lower()
        ]
    return listings


async def place_order(
    db: AsyncSession, buyer_earth_id: uuid.UUID, data: OrderCreate
) -> ServiceOrder:
    listing = await db.get(ServiceListing, data.listing_id)
    if listing is None or listing.status != SERVICE_ACTIVE:
        raise NotFoundError("سرویس یافت نشد یا فعال نیست.")
    if listing.provider_earth_id == buyer_earth_id:
        raise ForbiddenError("نمی‌توانید از خودتان سفارش دهید.")

    # ایجاد escrow
    payment_order = await payment_svc.create_escrow(
        db,
        payer_earth_id=buyer_earth_id,
        data=EscrowCreate(
            payee_earth_id=listing.provider_earth_id,
            amount_minor=data.agreed_price_minor,
            currency=data.currency.upper(),
            provider_code="sandbox",
        ),
    )

    order = ServiceOrder(
        listing_id=data.listing_id,
        buyer_earth_id=buyer_earth_id,
        provider_earth_id=listing.provider_earth_id,
        requirements=data.requirements,
        agreed_price_minor=data.agreed_price_minor,
        currency=data.currency.upper(),
        payment_order_id=payment_order.id,
        platform_fee_bps=PLATFORM_FEE_BPS,
    )
    db.add(order)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="marketplace.OrderPlaced",
            payload={"order_id": str(order.id), "buyer": str(buyer_earth_id)},
        ),
    )
    return order


async def _get_order(db: AsyncSession, order_id: uuid.UUID) -> ServiceOrder:
    order = await db.get(ServiceOrder, order_id)
    if order is None:
        raise NotFoundError("سفارش یافت نشد.")
    return order


async def accept_order(
    db: AsyncSession, order_id: uuid.UUID, provider_earth_id: uuid.UUID
) -> ServiceOrder:
    order = await _get_order(db, order_id)
    if order.provider_earth_id != provider_earth_id:
        raise ForbiddenError("فقط ارائه‌دهنده می‌تواند سفارش را قبول کند.")
    if order.status != ORDER_PENDING:
        raise ConflictError(f"وضعیت فعلی: {order.status}")
    order.status = ORDER_ACCEPTED
    await db.flush()
    return order


async def deliver_order(
    db: AsyncSession, order_id: uuid.UUID, provider_earth_id: uuid.UUID
) -> ServiceOrder:
    order = await _get_order(db, order_id)
    if order.provider_earth_id != provider_earth_id:
        raise ForbiddenError()
    if order.status not in (ORDER_ACCEPTED, ORDER_IN_PROGRESS):
        raise ConflictError(f"وضعیت فعلی: {order.status}")
    order.status = ORDER_DELIVERED
    await db.flush()
    return order


async def complete_order(
    db: AsyncSession, order_id: uuid.UUID, buyer_earth_id: uuid.UUID
) -> ServiceOrder:
    """خریدار تحویل را تأیید می‌کند → escrow آزاد می‌شود."""
    order = await _get_order(db, order_id)
    if order.buyer_earth_id != buyer_earth_id:
        raise ForbiddenError()
    if order.status != ORDER_DELIVERED:
        raise ConflictError("ابتدا تحویل انجام شود.")
    if order.payment_order_id:
        await payment_svc.capture(db, order.payment_order_id, buyer_earth_id)
    order.status = ORDER_COMPLETED
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="marketplace.OrderCompleted",
            payload={"order_id": str(order_id), "buyer": str(buyer_earth_id)},
        ),
    )
    return order
