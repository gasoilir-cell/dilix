"""Migration: جدول‌های نظرسنجی (message_polls + poll_votes) را می‌سازد."""
import asyncio
from app.core.database import engine, Base
from app.models.messages import MessagePoll, PollVote


async def main():
    async with engine.begin() as conn:
        await conn.run_sync(
            Base.metadata.create_all,
            tables=[MessagePoll.__table__, PollVote.__table__],
        )
    print("OK: message_polls / poll_votes ensured")


asyncio.run(main())
