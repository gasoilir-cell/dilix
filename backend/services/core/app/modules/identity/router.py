"""روتر Identity (سند ۵: /v1/identity/...)."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.identity import service
from app.modules.identity.roles import role_catalog
from app.modules.identity.schemas import (
    IdentityOut,
    ProfileUpdate,
    RoleChange,
    RoleOption,
    VisibilityUpdate,
)

router = APIRouter(prefix="/v1/identity", tags=["identity"])


@router.get("/me", response_model=IdentityOut)
async def get_me(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> IdentityOut:
    identity = await service.get_identity(db, user.earth_id)
    return IdentityOut.model_validate(identity, from_attributes=True)


@router.patch("/me", response_model=IdentityOut)
async def patch_me(
    data: ProfileUpdate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> IdentityOut:
    await service.update_profile(db, user.earth_id, data)
    identity = await service.get_identity(db, user.earth_id)
    return IdentityOut.model_validate(identity, from_attributes=True)


@router.put("/me/visibility", status_code=204)
async def put_visibility(
    data: VisibilityUpdate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await service.update_visibility(db, user.earth_id, data)


@router.get("/roles", response_model=list[RoleOption])
async def list_roles() -> list[RoleOption]:
    """کاتالوگِ نقش‌های خودسرویس که کاربر می‌تواند به آن‌ها سوییچ کند."""
    return [RoleOption(**item) for item in role_catalog()]


@router.post("/me/role", response_model=IdentityOut)
async def switch_role(
    data: RoleChange,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> IdentityOut:
    """سوییچِ نقشِ کاربر جاری (فقط نقش‌های خودسرویس)."""
    await service.change_role(db, user.earth_id, data.entity_type)
    identity = await service.get_identity(db, user.earth_id)
    return IdentityOut.model_validate(identity, from_attributes=True)
