"""روتر Social — /v1/social/..."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.social import service
from app.modules.social.schemas import (
    CommentCreate, CommentOut, PostCreate, PostOut, ReactionCreate,
)

router = APIRouter(prefix="/v1/social", tags=["social"])


@router.post("/posts", response_model=PostOut, status_code=201)
async def create_post(
    data: PostCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PostOut:
    post = await service.create_post(db, author_earth_id=user.earth_id, data=data)
    return PostOut.model_validate(post, from_attributes=True)


@router.delete("/posts/{post_id}", status_code=204)
async def delete_post(
    post_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await service.delete_post(db, post_id, user.earth_id)


@router.get("/feed", response_model=list[PostOut])
async def feed(
    limit: int = Query(default=20, le=100),
    post_type: str | None = Query(default=None, description="فیلترِ نوعِ پست، مثلاً reel"),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PostOut]:
    posts = await service.feed(db, user.earth_id, limit=limit, post_type=post_type)
    return [PostOut.model_validate(p, from_attributes=True) for p in posts]


@router.post("/posts/{post_id}/comments", response_model=CommentOut, status_code=201)
async def add_comment(
    post_id: uuid.UUID,
    data: CommentCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CommentOut:
    comment = await service.add_comment(db, post_id, user.earth_id, data)
    return CommentOut.model_validate(comment, from_attributes=True)


@router.post("/posts/{post_id}/reactions", response_model=PostOut)
async def react(
    post_id: uuid.UUID,
    data: ReactionCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PostOut:
    post = await service.react(db, post_id, user.earth_id, data)
    return PostOut.model_validate(post, from_attributes=True)


@router.post("/follow/{followee_id}", status_code=204)
async def follow(
    followee_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await service.follow(db, user.earth_id, followee_id)


@router.delete("/follow/{followee_id}", status_code=204)
async def unfollow(
    followee_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await service.unfollow(db, user.earth_id, followee_id)
