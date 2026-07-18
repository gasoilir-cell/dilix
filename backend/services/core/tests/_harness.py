"""هارنسِ مشترکِ تستِ یکپارچه برای ماژول‌های schema-qualified.

`build_module_client(schemas, model_modules)` یک context manager می‌سازد که:
engineِ SQLite با StaticPool + ATTACHِ schemaها + ساختِ جداولِ همان schemaها،
override روی `get_session`/`get_current_user`، و یک `AsyncClient` روی ASGI اپ را
برمی‌گرداند. تست‌ها با `state["user"]` می‌توانند کاربرِ جاری را عوض کنند.
"""
from __future__ import annotations

import contextlib
import importlib
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.pool import StaticPool


# روی SQLite ستونِ JSONB را مثلِ JSON بساز (فقط برای تست).
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


def set_user(state: dict, uid: uuid.UUID, region: str = "IR") -> uuid.UUID:
    from app.modules.auth.deps import CurrentUser

    state["user"] = CurrentUser(earth_id=uid, region=region)
    return uid


@contextlib.asynccontextmanager
async def build_module_client(schemas: tuple[str, ...], model_modules: tuple[str, ...]):
    for mod in model_modules:
        importlib.import_module(mod)
    from app.core.outbox import OutboxEvent  # noqa: F401
    from app.core.database import Base, get_session
    from app.main import app
    from app.modules.auth.deps import CurrentUser, get_current_user

    attach = tuple(dict.fromkeys((*schemas, "events")))
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    @event.listens_for(engine.sync_engine, "connect")
    def _attach(dbapi_conn, _record) -> None:  # noqa: ANN001
        cur = dbapi_conn.cursor()
        for name in attach:
            cur.execute(f"ATTACH DATABASE ':memory:' AS {name}")
        cur.close()

    tables = [t for t in Base.metadata.sorted_tables if t.schema in attach]
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
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            yield client, state
    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


async def assert_auth_required(method: str, path: str, expected: int = 403) -> None:
    """درخواستِ بدونِ توکن باید با ۴۰۳ (قراردادِ پروژه) رد شود."""
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.request(method, path)
    assert r.status_code == expected, r.text
