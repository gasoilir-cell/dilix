import asyncio
from sqlalchemy import text
from app.core.database import engine


async def main():
    async with engine.begin() as conn:
        await conn.execute(text("ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ"))
        await conn.execute(text("ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_by UUID"))
    print("OK: pinned_at/pinned_by ensured")


asyncio.run(main())
