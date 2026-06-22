"""لایه‌ی پایگاه‌داده‌ی async (SQLAlchemy 2.x).

طبق سند ۳: Database-per-Context. سرویس Core شامل schemaهای
identity / auth / authz / provider است؛ هیچ JOIN بین‌Contextی نباید نوشته شود.
"""
from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

_settings = get_settings()

engine = create_async_engine(
    _settings.database_url,
    echo=not _settings.is_production,
    pool_pre_ping=True,
)

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


class Base(DeclarativeBase):
    """پایه‌ی همه‌ی مدل‌های ORM در سرویس Core."""


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Dependency تزریق session به روترها."""
    async with SessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
