"""پیکربندیِ مشترکِ pytest + هارنسِ تستِ یکپارچه.

۱) پیش از هر import از `app.*`، `DILIX_DATABASE_URL` را روی SQLite درون‌حافظه‌ای
   ست می‌کند تا `app.core.database` هنگامِ ساختِ engine به asyncpg/Postgres نیاز
   نداشته باشد و `make core-test` بدونِ تنظیمِ دستیِ env سبز شود.

۲) فیکسچرِ `integration` یک هارنسِ کاملِ HTTP می‌سازد: engineِ SQLite با StaticPool
   (اشتراکِ همان دیتابیسِ درون‌حافظه بین اتصال‌ها) + ATTACHِ schemaهای
   `stickers`/`stories` (تا جداولِ schema-qualified ساخته شوند)، override روی
   `get_session` و `get_current_user`، و یک `httpx.AsyncClient` روی ASGI اپ.
   تست‌ها با `harness.as_user(...)` می‌توانند کاربرِ جاری را عوض کنند.
"""
from __future__ import annotations

import os

os.environ.setdefault("DILIX_DATABASE_URL", "sqlite+aiosqlite:///:memory:")

import uuid  # noqa: E402

import pytest_asyncio  # noqa: E402
from sqlalchemy import event  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool  # noqa: E402

_ATTACHED_SCHEMAS = ("stickers", "stories")


class IntegrationHarness:
    """کلاینتِ HTTP + قابلیتِ تعویضِ کاربرِ احرازشده در طولِ تست."""

    def __init__(self, client, state: dict) -> None:
        self.client = client
        self._state = state

    def as_user(self, earth_id: uuid.UUID | None = None, region: str = "IR") -> uuid.UUID:
        from app.modules.auth.deps import CurrentUser

        uid = earth_id or uuid.uuid4()
        self._state["user"] = CurrentUser(earth_id=uid, region=region)
        return uid

    @property
    def earth_id(self) -> uuid.UUID:
        return self._state["user"].earth_id


@pytest_asyncio.fixture
async def integration() -> IntegrationHarness:
    from httpx import ASGITransport, AsyncClient

    # register شدنِ جداولِ دو ماژول روی metadata با alias — تا `import app.modules...`
    # نامِ محلیِ `app` (نمونهٔ FastAPI) را با پکیجِ `app` overwrite نکند.
    import app.modules.stickers.models as _stickers_models  # noqa: F401
    import app.modules.stories.models as _stories_models  # noqa: F401

    from app.core.database import Base, get_session
    from app.main import app
    from app.modules.auth.deps import CurrentUser, get_current_user

    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    @event.listens_for(engine.sync_engine, "connect")
    def _attach_schemas(dbapi_conn, _record) -> None:  # noqa: ANN001
        cur = dbapi_conn.cursor()
        for name in _ATTACHED_SCHEMAS:
            cur.execute(f"ATTACH DATABASE ':memory:' AS {name}")
        cur.close()

    tables = [t for t in Base.metadata.sorted_tables if t.schema in _ATTACHED_SCHEMAS]
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=tables))

    Session = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)

    async def _override_session():
        async with Session() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    state: dict = {"user": CurrentUser(earth_id=uuid.uuid4(), region="IR")}

    async def _override_user() -> CurrentUser:
        return state["user"]

    app.dependency_overrides[get_session] = _override_session
    app.dependency_overrides[get_current_user] = _override_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield IntegrationHarness(client, state)

    app.dependency_overrides.clear()
    await engine.dispose()
