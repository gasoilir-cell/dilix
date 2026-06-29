"""منطق ثبت‌نام ارائه‌دهنده و API. KYB در وضعیت pending شروع می‌شود."""
from __future__ import annotations

import hashlib
import secrets
import time
import uuid

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.provider.models import (
    Provider,
    ProviderApi,
    ProviderCredential,
    ProviderWebhook,
)
from app.modules.provider.schemas import (
    CredentialCreate,
    ProviderApiCreate,
    ProviderRegisterRequest,
    WebhookCreate,
)

_SANDBOX_TEST_TIMEOUT_S = 8.0


def _hash_key(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()


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


async def _get_provider_or_404(db: AsyncSession, provider_id: uuid.UUID) -> Provider:
    provider = await db.get(Provider, provider_id)
    if provider is None:
        raise NotFoundError("ارائه‌دهنده یافت نشد.")
    return provider


async def sandbox_test(
    db: AsyncSession, provider_id: uuid.UUID, api_id: uuid.UUID
) -> dict:
    """اجرای تستِ دسترس‌پذیریِ sandbox روی spec_url ثبت‌شده‌ی API."""
    await _get_provider_or_404(db, provider_id)
    api = await db.get(ProviderApi, api_id)
    if api is None or api.provider_id != provider_id:
        raise NotFoundError("API یافت نشد.")

    if not api.spec_url:
        return {
            "api_id": api_id,
            "reachable": False,
            "http_status": None,
            "latency_ms": None,
            "detail": "spec_url ثبت نشده است؛ تست ممکن نیست.",
        }

    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(timeout=_SANDBOX_TEST_TIMEOUT_S) as client:
            resp = await client.get(api.spec_url)
        latency = int((time.perf_counter() - started) * 1000)
        reachable = resp.status_code < 500
        if reachable and api.status == "draft":
            api.status = "tested"
        await db.flush()
        return {
            "api_id": api_id,
            "reachable": reachable,
            "http_status": resp.status_code,
            "latency_ms": latency,
            "detail": "spec در دسترس است." if reachable else "پاسخِ خطای سرور از مقصد.",
        }
    except httpx.HTTPError as exc:
        latency = int((time.perf_counter() - started) * 1000)
        return {
            "api_id": api_id,
            "reachable": False,
            "http_status": None,
            "latency_ms": latency,
            "detail": f"دسترسی ناموفق: {exc.__class__.__name__}",
        }


async def register_webhook(
    db: AsyncSession, provider_id: uuid.UUID, data: WebhookCreate
) -> ProviderWebhook:
    await _get_provider_or_404(db, provider_id)
    webhook = ProviderWebhook(
        provider_id=provider_id,
        url=data.url,
        event_types=data.event_types,
        secret=secrets.token_urlsafe(32),
        status="active",
    )
    db.add(webhook)
    await db.flush()
    return webhook


async def issue_credential(
    db: AsyncSession, provider_id: uuid.UUID, data: CredentialCreate
) -> tuple[ProviderCredential, str]:
    """صدورِ کلیدِ API. کلیدِ خام فقط همین‌جا برمی‌گردد؛ در DB فقط hash می‌ماند."""
    provider = await _get_provider_or_404(db, provider_id)
    # کلیدِ production فقط برای ارائه‌دهنده‌ی KYB-verified
    if data.env == "production" and provider.kyb_status != "verified":
        raise ForbiddenError("کلیدِ production نیازمندِ تأییدِ KYB است.")

    raw_key = f"dlx_{data.env[:4]}_{secrets.token_urlsafe(32)}"
    cred = ProviderCredential(
        provider_id=provider_id,
        env=data.env,
        key_prefix=raw_key[:12],
        key_hash=_hash_key(raw_key),
        status="active",
    )
    db.add(cred)
    await db.flush()
    return cred, raw_key
