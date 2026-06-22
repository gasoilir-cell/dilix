"""منطق ثبت‌نام ارائه‌دهنده و API. KYB در وضعیت pending شروع می‌شود."""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.provider.models import Provider, ProviderApi
from app.modules.provider.schemas import ProviderApiCreate, ProviderRegisterRequest


async def register_provider(
    db: AsyncSession, data: ProviderRegisterRequest
) -> Provider:
    provider = Provider(
        legal_name=data.legal_name,
        provider_type=data.provider_type,
        country=data.country,
        license_no=data.license_no,
        kyb_status="pending",
    )
    db.add(provider)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="provider.ProviderRegistered",
            payload={"provider_id": str(provider.id), "type": data.provider_type},
        ),
    )
    return provider


async def register_api(
    db: AsyncSession, provider_id: uuid.UUID, data: ProviderApiCreate
) -> ProviderApi:
    provider = await db.get(Provider, provider_id)
    if provider is None:
        raise NotFoundError("ارائه‌دهنده یافت نشد.")
    # فقط ارائه‌دهنده‌ی تأییدشده می‌تواند به production برود؛ ثبت در sandbox آزاد است.
    if provider.kyb_status == "rejected":
        raise ForbiddenError("KYB این ارائه‌دهنده رد شده است.")

    api = ProviderApi(
        provider_id=provider_id,
        name=data.name,
        spec_url=data.spec_url,
        webhook_url=data.webhook_url,
        env="sandbox",
        status="draft",
    )
    db.add(api)
    await db.flush()
    return api


async def list_apis(db: AsyncSession, provider_id: uuid.UUID) -> list[ProviderApi]:
    result = await db.execute(
        select(ProviderApi).where(ProviderApi.provider_id == provider_id)
    )
    return list(result.scalars().all())
