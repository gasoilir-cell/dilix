"""baseline اولیه — ساختِ همه schemaها و جداولِ سرویسِ Core.

این مهاجرت baseline است: ابتدا همه‌ی schemaهای دامنه ساخته می‌شوند و سپس همه‌ی
جداول از روی `Base.metadata` (که env.py همه‌ی مدل‌ها را در آن ثبت کرده) ایجاد می‌شوند.
مهاجرت‌های بعدی با autogenerate به‌صورتِ افزایشی نوشته می‌شوند.

Revision ID: 0001_initial_baseline
Revises:
Create Date: 2026-06-23
"""
from __future__ import annotations

from alembic import op

from app.core.database import Base

EXCLUDED_FUTURE_SCHEMAS = {"stickers", "stories"}

# شناسه‌های Alembic
revision = "0001_initial_baseline"
down_revision = None
branch_labels = None
depends_on = None

# همه‌ی schemaهای دامنه (Database-per-Context، سند ۳)
SCHEMAS = (
    "ai",
    "auth",
    "carrier",
    "discovery",
    "earth",
    "events",
    "freight",
    "gamification",
    "identity",
    "insurance",
    "investment",
    "kyc",
    "marketplace",
    "membership",
    "messaging",
    "notification",
    "payments",
    "provider",
    "referral",
    "reputation",
    "social",
    "stickers",
    "stories",
    "telecom",
)


def upgrade() -> None:
    bind = op.get_bind()
    for schema in SCHEMAS:
        op.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}"')
    # ساختِ جداولِ ثبت‌شده در baseline؛ جدول‌های مهاجرت‌های بعدی این‌جا ساخته نمی‌شوند.
    for table in Base.metadata.sorted_tables:
        if table.schema not in EXCLUDED_FUTURE_SCHEMAS:
            table.create(bind=bind, checkfirst=True)


def downgrade() -> None:
    bind = op.get_bind()
    for table in reversed(Base.metadata.sorted_tables):
        if table.schema not in EXCLUDED_FUTURE_SCHEMAS:
            table.drop(bind=bind, checkfirst=True)
    for schema in SCHEMAS:
        op.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')
