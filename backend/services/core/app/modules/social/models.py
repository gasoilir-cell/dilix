"""مدل ORM شبکه‌ی اجتماعی — پست، کامنت، ری‌اکشن، فالو (schema: social)."""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

POST_TEXT = "text"
POST_IMAGE = "image"
POST_VIDEO = "video"
POST_STORY = "story"
POST_REEL = "reel"

POST_PUBLIC = "public"
POST_CONNECTIONS = "connections"
POST_PRIVATE = "private"


class SocialPost(Base):
    __tablename__ = "social_post"
    __table_args__ = {"schema": "social"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    author_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    post_type: Mapped[str] = mapped_column(String(16), default=POST_TEXT, nullable=False)
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    # [{type: image/video, ref: "minio-key", thumb: "..."}]
    media: Mapped[dict] = mapped_column(JSONB, default=list, nullable=False)
    visibility: Mapped[str] = mapped_column(String(16), default=POST_PUBLIC, nullable=False)
    reaction_counts: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    comment_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class PostComment(Base):
    __tablename__ = "post_comment"
    __table_args__ = {"schema": "social"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("social.social_post.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    author_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    parent_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class PostReaction(Base):
    __tablename__ = "post_reaction"
    __table_args__ = {"schema": "social"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    reactor_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    reaction: Mapped[str] = mapped_column(String(32), nullable=False)  # like, love, wow …
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Follow(Base):
    """فالو / آن‌فالو — گرافِ اجتماعی."""

    __tablename__ = "follow"
    __table_args__ = {"schema": "social"}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    follower_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    followee_earth_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
