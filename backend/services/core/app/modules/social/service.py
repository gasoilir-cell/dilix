"""سرویس Social — پست، کامنت، ری‌اکشن، فالو."""
from __future__ import annotations

import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.social.models import Follow, PostComment, PostReaction, SocialPost
from app.modules.social.schemas import CommentCreate, PostCreate, ReactionCreate


async def create_post(
    db: AsyncSession, *, author_earth_id: uuid.UUID, data: PostCreate
) -> SocialPost:
    post = SocialPost(
        author_earth_id=author_earth_id,
        post_type=data.post_type,
        content=data.content,
        media=data.media,
        visibility=data.visibility,
    )
    db.add(post)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent("social.PostCreated", {"post_id": str(post.id)}),
    )
    return post


async def _load_post(db: AsyncSession, post_id: uuid.UUID) -> SocialPost:
    post = await db.get(SocialPost, post_id)
    if post is None or post.deleted:
        raise NotFoundError("پست یافت نشد.")
    return post


async def delete_post(
    db: AsyncSession, post_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> None:
    post = await _load_post(db, post_id)
    if post.author_earth_id != actor_earth_id:
        raise ForbiddenError("فقط نویسنده می‌تواند پست را حذف کند.")
    post.deleted = True
    await db.flush()


async def add_comment(
    db: AsyncSession, post_id: uuid.UUID, author_earth_id: uuid.UUID, data: CommentCreate
) -> PostComment:
    post = await _load_post(db, post_id)
    comment = PostComment(
        post_id=post_id,
        author_earth_id=author_earth_id,
        content=data.content,
        parent_id=data.parent_id,
    )
    db.add(comment)
    post.comment_count += 1
    await db.flush()
    return comment


async def react(
    db: AsyncSession, post_id: uuid.UUID, reactor_earth_id: uuid.UUID, data: ReactionCreate
) -> SocialPost:
    post = await _load_post(db, post_id)
    # حذفِ ری‌اکشنِ قبلیِ همین کاربر روی همین پست
    await db.execute(
        delete(PostReaction).where(
            PostReaction.post_id == post_id,
            PostReaction.reactor_earth_id == reactor_earth_id,
        )
    )
    db.add(PostReaction(post_id=post_id, reactor_earth_id=reactor_earth_id, reaction=data.reaction))
    counts = dict(post.reaction_counts)
    counts[data.reaction] = counts.get(data.reaction, 0) + 1
    post.reaction_counts = counts
    await db.flush()
    return post


async def follow(
    db: AsyncSession, follower_earth_id: uuid.UUID, followee_earth_id: uuid.UUID
) -> None:
    if follower_earth_id == followee_earth_id:
        raise ConflictError("نمی‌توانید خودتان را فالو کنید.")
    existing = await db.execute(
        select(Follow).where(
            Follow.follower_earth_id == follower_earth_id,
            Follow.followee_earth_id == followee_earth_id,
        )
    )
    if existing.scalars().first():
        raise ConflictError("قبلاً فالو کرده‌اید.")
    db.add(Follow(follower_earth_id=follower_earth_id, followee_earth_id=followee_earth_id))
    await db.flush()


async def unfollow(
    db: AsyncSession, follower_earth_id: uuid.UUID, followee_earth_id: uuid.UUID
) -> None:
    await db.execute(
        delete(Follow).where(
            Follow.follower_earth_id == follower_earth_id,
            Follow.followee_earth_id == followee_earth_id,
        )
    )
    await db.flush()


async def feed(
    db: AsyncSession, viewer_earth_id: uuid.UUID, limit: int = 20
) -> list[SocialPost]:
    """فیدِ ساده: پست‌های جدیدِ کسانی که فالو می‌کنیم."""
    followees_result = await db.execute(
        select(Follow.followee_earth_id).where(
            Follow.follower_earth_id == viewer_earth_id
        )
    )
    followees = [r for r in followees_result.scalars().all()]
    if not followees:
        return []
    result = await db.execute(
        select(SocialPost)
        .where(SocialPost.author_earth_id.in_(followees), SocialPost.deleted.is_(False))
        .order_by(SocialPost.created_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())
