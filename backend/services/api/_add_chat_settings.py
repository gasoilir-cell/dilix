"""Migration: user_blocks table + room_members.muted_until/cleared_at columns."""
import asyncio
from sqlalchemy import text
from app.core.database import engine, Base
from app.models.messages import UserBlock


async def main():
    async with engine.begin() as conn:
        # جدولِ جدیدِ مسدودسازی
        await conn.run_sync(Base.metadata.create_all, tables=[UserBlock.__table__])
        # ستون‌های جدید روی room_members (create_all ستونِ جدید نمی‌سازد)
        await conn.execute(text(
            "ALTER TABLE room_members ADD COLUMN IF NOT EXISTS muted_until TIMESTAMPTZ"
        ))
        await conn.execute(text(
            "ALTER TABLE room_members ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ"
        ))
    print("OK: user_blocks ensured; room_members.muted_until/cleared_at ensured")


asyncio.run(main())
