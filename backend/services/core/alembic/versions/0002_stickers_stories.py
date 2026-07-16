"""stickers و stories — schema و tableهای رسمی.

Revision ID: 0002_stickers_stories
Revises: 0001_initial_baseline
Create Date: 2026-07-13
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002_stickers_stories"
down_revision = "0001_initial_baseline"
branch_labels = None
depends_on = None

UUID = postgresql.UUID(as_uuid=True)


def upgrade() -> None:
    op.execute('CREATE SCHEMA IF NOT EXISTS "stickers"')
    op.execute('CREATE SCHEMA IF NOT EXISTS "stories"')

    op.create_table(
        "sticker_pack",
        sa.Column("id", UUID, nullable=False),
        sa.Column("owner_earth_id", UUID, nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("description", sa.String(length=300), nullable=True),
        sa.Column("cover_url", sa.String(length=500), nullable=True),
        sa.Column("is_public", sa.Boolean(), nullable=False),
        sa.Column("is_animated", sa.Boolean(), nullable=False),
        sa.Column("install_count", sa.Integer(), nullable=False),
        sa.Column("sticker_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        schema="stickers",
    )
    op.create_index("ix_stickers_sticker_pack_owner_earth_id", "sticker_pack", ["owner_earth_id"], schema="stickers")
    op.create_index("ix_stickers_sticker_pack_is_public", "sticker_pack", ["is_public"], schema="stickers")

    op.create_table(
        "sticker",
        sa.Column("id", UUID, nullable=False),
        sa.Column("pack_id", UUID, nullable=False),
        sa.Column("owner_earth_id", UUID, nullable=False),
        sa.Column("media_url", sa.String(length=500), nullable=False),
        sa.Column("media_type", sa.String(length=32), nullable=False),
        sa.Column("emoji_tag", sa.String(length=32), nullable=True),
        sa.Column("title", sa.String(length=120), nullable=True),
        sa.Column("use_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["pack_id"], ["stickers.sticker_pack.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        schema="stickers",
    )
    op.create_index("ix_stickers_sticker_pack_id", "sticker", ["pack_id"], schema="stickers")
    op.create_index("ix_stickers_sticker_owner_earth_id", "sticker", ["owner_earth_id"], schema="stickers")

    op.create_table(
        "starred_sticker",
        sa.Column("id", UUID, nullable=False),
        sa.Column("user_earth_id", UUID, nullable=False),
        sa.Column("sticker_id", UUID, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["sticker_id"], ["stickers.sticker.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        schema="stickers",
    )
    op.create_index("ix_stickers_starred_sticker_user_earth_id", "starred_sticker", ["user_earth_id"], schema="stickers")
    op.create_index("ix_stickers_starred_sticker_sticker_id", "starred_sticker", ["sticker_id"], schema="stickers")
    op.create_index("uq_starred_sticker", "starred_sticker", ["user_earth_id", "sticker_id"], unique=True, schema="stickers")

    op.create_table(
        "installed_pack",
        sa.Column("id", UUID, nullable=False),
        sa.Column("user_earth_id", UUID, nullable=False),
        sa.Column("pack_id", UUID, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["pack_id"], ["stickers.sticker_pack.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        schema="stickers",
    )
    op.create_index("ix_stickers_installed_pack_user_earth_id", "installed_pack", ["user_earth_id"], schema="stickers")
    op.create_index("ix_stickers_installed_pack_pack_id", "installed_pack", ["pack_id"], schema="stickers")
    op.create_index("uq_installed_pack", "installed_pack", ["user_earth_id", "pack_id"], unique=True, schema="stickers")

    op.create_table(
        "story",
        sa.Column("id", UUID, nullable=False),
        sa.Column("author_earth_id", UUID, nullable=False),
        sa.Column("media_url", sa.Text(), nullable=False),
        sa.Column("media_type", sa.String(length=12), nullable=False),
        sa.Column("caption", sa.Text(), nullable=True),
        sa.Column("audience", sa.String(length=16), nullable=False),
        sa.Column("view_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        schema="stories",
    )
    op.create_index("ix_stories_story_author_earth_id", "story", ["author_earth_id"], schema="stories")
    op.create_index("ix_stories_story_created_at", "story", ["created_at"], schema="stories")
    op.create_index("ix_stories_story_expires_at", "story", ["expires_at"], schema="stories")
    op.create_index("ix_story_author_exp", "story", ["author_earth_id", "expires_at"], schema="stories")

    op.create_table(
        "contact_circle",
        sa.Column("id", UUID, nullable=False),
        sa.Column("owner_earth_id", UUID, nullable=False),
        sa.Column("member_earth_id", UUID, nullable=False),
        sa.Column("circle", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        schema="stories",
    )
    op.create_index("ix_stories_contact_circle_owner_earth_id", "contact_circle", ["owner_earth_id"], schema="stories")
    op.create_index("ix_stories_contact_circle_member_earth_id", "contact_circle", ["member_earth_id"], schema="stories")
    op.create_index("uq_contact_circle", "contact_circle", ["owner_earth_id", "member_earth_id", "circle"], unique=True, schema="stories")
    op.create_index("ix_contact_circle_member", "contact_circle", ["member_earth_id", "circle"], schema="stories")

    op.create_table(
        "story_view",
        sa.Column("id", UUID, nullable=False),
        sa.Column("story_id", UUID, nullable=False),
        sa.Column("viewer_earth_id", UUID, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["story_id"], ["stories.story.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        schema="stories",
    )
    op.create_index("ix_stories_story_view_story_id", "story_view", ["story_id"], schema="stories")
    op.create_index("ix_stories_story_view_viewer_earth_id", "story_view", ["viewer_earth_id"], schema="stories")
    op.create_index("uq_story_view", "story_view", ["story_id", "viewer_earth_id"], unique=True, schema="stories")


def downgrade() -> None:
    op.drop_index("uq_story_view", table_name="story_view", schema="stories")
    op.drop_index("ix_stories_story_view_viewer_earth_id", table_name="story_view", schema="stories")
    op.drop_index("ix_stories_story_view_story_id", table_name="story_view", schema="stories")
    op.drop_table("story_view", schema="stories")
    op.drop_index("ix_contact_circle_member", table_name="contact_circle", schema="stories")
    op.drop_index("uq_contact_circle", table_name="contact_circle", schema="stories")
    op.drop_index("ix_stories_contact_circle_member_earth_id", table_name="contact_circle", schema="stories")
    op.drop_index("ix_stories_contact_circle_owner_earth_id", table_name="contact_circle", schema="stories")
    op.drop_table("contact_circle", schema="stories")
    op.drop_index("ix_story_author_exp", table_name="story", schema="stories")
    op.drop_index("ix_stories_story_expires_at", table_name="story", schema="stories")
    op.drop_index("ix_stories_story_created_at", table_name="story", schema="stories")
    op.drop_index("ix_stories_story_author_earth_id", table_name="story", schema="stories")
    op.drop_table("story", schema="stories")
    op.drop_index("uq_installed_pack", table_name="installed_pack", schema="stickers")
    op.drop_index("ix_stickers_installed_pack_pack_id", table_name="installed_pack", schema="stickers")
    op.drop_index("ix_stickers_installed_pack_user_earth_id", table_name="installed_pack", schema="stickers")
    op.drop_table("installed_pack", schema="stickers")
    op.drop_index("uq_starred_sticker", table_name="starred_sticker", schema="stickers")
    op.drop_index("ix_stickers_starred_sticker_sticker_id", table_name="starred_sticker", schema="stickers")
    op.drop_index("ix_stickers_starred_sticker_user_earth_id", table_name="starred_sticker", schema="stickers")
    op.drop_table("starred_sticker", schema="stickers")
    op.drop_index("ix_stickers_sticker_owner_earth_id", table_name="sticker", schema="stickers")
    op.drop_index("ix_stickers_sticker_pack_id", table_name="sticker", schema="stickers")
    op.drop_table("sticker", schema="stickers")
    op.drop_index("ix_stickers_sticker_pack_is_public", table_name="sticker_pack", schema="stickers")
    op.drop_index("ix_stickers_sticker_pack_owner_earth_id", table_name="sticker_pack", schema="stickers")
    op.drop_table("sticker_pack", schema="stickers")
    op.execute('DROP SCHEMA IF EXISTS "stories" CASCADE')
    op.execute('DROP SCHEMA IF EXISTS "stickers" CASCADE')
