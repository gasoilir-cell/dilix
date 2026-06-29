"""روتر Provider (سند ۵: /v1/providers/...)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.provider import service
from app.modules.provider.schemas import (
    CredentialCreate,
    CredentialOut,
    ProviderApiCreate,
    ProviderApiOut,
    ProviderOut,
    ProviderRegisterRequest,
    SandboxTestResult,
    WebhookCreate,
    WebhookOut,
)

router = APIRouter(prefix="/v1/providers", tags=["provider"])


@router.post("/register", response_model=ProviderOut, status_code=201)
async def register_provider(
    data: ProviderRegisterRequest,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ProviderOut:
    provider = await service.register_provider(db, data)
    return ProviderOut.model_validate(provider, from_attributes=True)


@router.post("/{provider_id}/apis", response_model=ProviderApiOut, status_code=201)
async def register_api(
    provider_id: uuid.UUID,
    data: ProviderApiCreate,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ProviderApiOut:
    api = await service.register_api(db, provider_id, data)
    return ProviderApiOut.model_validate(api, from_attributes=True)


@router.get("/{provider_id}/apis", response_model=list[ProviderApiOut])
async def list_apis(
    provider_id: uuid.UUID,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ProviderApiOut]:
    apis = await service.list_apis(db, provider_id)
    return [ProviderApiOut.model_validate(a, from_attributes=True) for a in apis]


@router.post(
    "/{provider_id}/apis/{api_id}/sandbox-test",
    response_model=SandboxTestResult,
)
async def sandbox_test(
    provider_id: uuid.UUID,
    api_id: uuid.UUID,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> SandboxTestResult:
    """تستِ دسترس‌پذیریِ sandbox روی API ثبت‌شده‌ی ارائه‌دهنده."""
    result = await service.sandbox_test(db, provider_id, api_id)
    return SandboxTestResult(**result)


@router.post(
    "/{provider_id}/webhooks",
    response_model=WebhookOut,
    status_code=201,
)
async def register_webhook(
    provider_id: uuid.UUID,
    data: WebhookCreate,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> WebhookOut:
    """ثبتِ webhook؛ secretِ امضای HMAC فقط همین‌جا برمی‌گردد."""
    webhook = await service.register_webhook(db, provider_id, data)
    return WebhookOut(
        id=webhook.id,
        url=webhook.url,
        event_types=webhook.event_types,
        status=webhook.status,
        secret=webhook.secret,
    )


@router.post(
    "/{provider_id}/credentials",
    response_model=CredentialOut,
    status_code=201,
)
async def issue_credential(
    provider_id: uuid.UUID,
    data: CredentialCreate,
    _user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CredentialOut:
    """صدورِ کلیدِ sandbox/production؛ کلیدِ خام فقط همین‌جا برمی‌گردد."""
    cred, raw_key = await service.issue_credential(db, provider_id, data)
    return CredentialOut(
        id=cred.id,
        env=cred.env,
        key_prefix=cred.key_prefix,
        status=cred.status,
        api_key=raw_key,
    )
