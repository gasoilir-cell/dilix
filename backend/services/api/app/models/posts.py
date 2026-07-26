"""
Dilix — Posts (پستِ عکس/ویدیو + فیدِ اجتماعی، مثل اینستاگرام Feed)
لایک/کامنت/ذخیره (bookmark)؛ فیدِ دنبال‌شونده‌ها + کاوشِ عمومی.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Text, Index
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class Post(Base):
    """یک پستِ رسانه‌ای (عکس/ویدیو) در فید."""
    __tablename__ = "posts"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    author_id     = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    media_url     = Column(Text, nullable=False)
    media_type    = Column(String(12), nullable=False, default="image")  # image | video
    caption       = Column(Text, nullable=True)
    like_count    = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    save_count    = Column(Integer, default=0)
    # موقعیتِ جغرافیایی (اختیاری) — «لحظه‌ها»: پیوندِ پست با نقطه‌ای روی کره
    lat           = Column(Float, nullable=True)
    lng           = Column(Float, nullable=True)
    place_name    = Column(String(120), nullable=True)
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)

    __table_args__ = (
        Index("ix_post_author_created", "author_id", "created_at"),
        Index("ix_post_geo", "lat", "lng"),
    )


class PostLike(Base):
    __tablename__ = "post_likes"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_post_like", "post_id", "user_id", unique=True),
    )


class PostComment(Base):
    __tablename__ = "post_comments"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id  = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    body       = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)


class PostSave(Base):
    """ذخیره/بوکمارکِ پست."""
    __tablename__ = "post_saves"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)

    __table_args__ = (
        Index("uq_post_save", "post_id", "user_id", unique=True),
    )


class PostHashtag(Base):
    """
    هشتگِ استخراج‌شده از کپشنِ پست — پایهٔ «کاوشِ بر پایهٔ علاقه» و موضوع‌های داغ.
    `created_at` کپیِ زمانِ پست است تا شمارشِ trending در بازهٔ اخیر ساده باشد.
    """
    __tablename__ = "post_hashtags"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id    = Column(UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    tag        = Column(String(80), nullable=False, index=True)  # نرمال‌شده: بدونِ #، حروفِ کوچک
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)

    __table_args__ = (
        Index("uq_post_hashtag", "post_id", "tag", unique=True),
        Index("ix_hashtag_tag_created", "tag", "created_at"),
    )
