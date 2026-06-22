"""سرویس تلکام — شارژ و eSIM."""
from __future__ import annotations
import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from dilix_shared.adapter import AdapterError
from dilix_shared.errors import ProviderError
from dilix_shared.events import DomainEvent
from app.core.events import publisher
from app.modules.telecom.adapters import telecom_registry
from app.modules.telecom.models import EsimProfile, TopUpOrder
from app.modules.telecom.ports import EsimActivationRequest, TopUpRequest
from app.modules.telecom.schemas import EsimCreate, TopUpCreate


async def top_up(db: AsyncSession, *, earth_id: uuid.UUID, data: TopUpCreate) -> TopUpOrder:
    adapter = telecom_registry.get(data.provider_code)
    try:
        result = await adapter.top_up(TopUpRequest(
            subscriber_ref=str(earth_id), msisdn=data.msisdn,
            amount_minor=data.amount_minor, currency=data.currency.upper(),
            product_code=data.product_code,
        ))
    except AdapterError as exc:
        raise ProviderError(exc.detail) from exc
    order = TopUpOrder(
        earth_id=earth_id, provider_code=data.provider_code, msisdn=data.msisdn,
        product_code=data.product_code, amount_minor=data.amount_minor,
        currency=data.currency.upper(), external_ref=result.external_ref,
        status=result.status,
    )
    db.add(order)
    await db.flush()
    await publisher.publish(db, DomainEvent("telecom.TopUpCompleted", {"order_id": str(order.id)}))
    return order


async def activate_esim(db: AsyncSession, *, earth_id: uuid.UUID, data: EsimCreate) -> EsimProfile:
    adapter = telecom_registry.get(data.provider_code)
    try:
        result = await adapter.activate_esim(EsimActivationRequest(
            subscriber_ref=str(earth_id), iccid=data.iccid, country_code=data.country_code,
        ))
    except AdapterError as exc:
        raise ProviderError(exc.detail) from exc
    profile = EsimProfile(
        earth_id=earth_id, provider_code=data.provider_code,
        iccid=data.iccid, country_code=data.country_code, status=result.status,
    )
    db.add(profile)
    await db.flush()
    return profile
