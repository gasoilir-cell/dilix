"""پیکربندی Alembic برای مهاجرت‌های async (سند ۳: expand/contract)."""
from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import async_engine_from_config
from sqlalchemy import pool

from app.core.config import get_settings
from app.core.database import Base

# وارد کردن مدل‌ها تا در metadata ثبت شوند
from app.core import outbox as _outbox  # noqa: F401
from app.modules.identity import models as _identity  # noqa: F401
from app.modules.auth import models as _auth  # noqa: F401
from app.modules.provider import models as _provider  # noqa: F401
from app.modules.payments import models as _payments  # noqa: F401
from app.modules.insurance import models as _insurance  # noqa: F401
from app.modules.carrier import models as _carrier  # noqa: F401
from app.modules.kyc import models as _kyc  # noqa: F401
from app.modules.freight import models as _freight  # noqa: F401
from app.modules.messaging import models as _messaging  # noqa: F401
from app.modules.social import models as _social  # noqa: F401
from app.modules.stickers import models as _stickers  # noqa: F401
from app.modules.stories import models as _stories  # noqa: F401
from app.modules.notification import models as _notification  # noqa: F401
from app.modules.referral import models as _referral  # noqa: F401
from app.modules.gamification import models as _gamification  # noqa: F401
from app.modules.membership import models as _membership  # noqa: F401
from app.modules.telecom import models as _telecom  # noqa: F401
from app.modules.investment import models as _investment  # noqa: F401
from app.modules.ai import models as _ai  # noqa: F401
from app.modules.earth import models as _earth  # noqa: F401
from app.modules.discovery import models as _discovery  # noqa: F401
from app.modules.reputation import models as _reputation  # noqa: F401
from app.modules.marketplace import models as _marketplace  # noqa: F401

config = context.config
config.set_main_option("sqlalchemy.url", get_settings().database_url)
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def do_run_migrations(connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_schemas=True,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


def run_migrations_offline() -> None:
    """حالتِ offline: تولیدِ SQL بدونِ اتصال به DB (`alembic upgrade head --sql`)."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        include_schemas=True,
        compare_type=True,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
