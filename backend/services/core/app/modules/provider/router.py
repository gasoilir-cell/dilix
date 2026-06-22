"""روتر Provider (سند ۵: /v1/providers/...)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.provider import service
from app.modules.provider.schemas import (
    ProviderApiCreate,
    ProviderApiOut,
    ProviderOut,
    ProviderRegisterRequest,
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
