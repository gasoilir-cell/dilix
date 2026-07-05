import asyncio
from sqlalchemy import text
from app.core.database import engine


async def main():
    async with engine.begin() as conn:
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ"
        ))
    print("OK: last_seen_at ensured")


asyncio.run(main())
