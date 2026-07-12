"""تستِ یکپارچهٔ HTTP برای Discovery (GET /v1/discovery/nearby و contact-request).

جریانی که صفحهٔ وبِ discovery اجرا می‌کند: جستجوی اطراف (روی جداولِ خالی → لیستِ
خالی) و گاردهای درخواستِ تماس (به‌خود=۴۰۹، هدفِ ناموجود=۴۰۴). engineِ مستقل با
ATTACHِ schemaهای لازمِ join (`earth`/`identity`/`social`/`discovery`/`events`) +
shimِ `JSONB→JSON`. ساختار مطابقِ test_telecom_integration.
"""
from __future__ import annotations

import uuid

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.pool import StaticPool

_SCHEMAS = ("earth", "identity", "social", "discovery", "events")


# روی SQLite نوع‌های خاصِ Postgres را قابلِ ساخت کن (فقط برای تست؛ جداول خالی‌اند).
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@compiles(ARRAY, "sqlite")
def _compile_array_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def disc_client():
    import app.modules.earth.models as _earth_models  # noqa: F401
    import app.modules.identity.models as _identity_models  # noqa: F401
    import app.modules.social.models as _social_models  # noqa: F401
    import app.modules.discovery.models as _discovery_models  # noqa: F401
    from app.core.outbox import OutboxEvent  # noqa: F401
    from app.core.database import Base, get_session
    from app.main import app
    from app.modules.auth.deps import CurrentUser, get_current_user

    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    @event.listens_for(engine.sync_engine, "connect")
    def _attach(dbapi_conn, _record) -> None:  # noqa: ANN001
        cur = dbapi_conn.cursor()
        for name in _SCHEMAS:
            cur.execute(f"ATTACH DATABASE ':memory:' AS {name}")
        cur.close()

    tables = [t for t in Base.metadata.sorted_tables if t.schema in _SCHEMAS]
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

    state = {"user": CurrentUser(earth_id=uuid.uuid4(), region="IR")}

    async def _override_user() -> CurrentUser:
        return state["user"]

    app.dependency_overrides[get_session] = _override_session
    app.dependency_overrides[get_current_user] = _override_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client, state

    app.dependency_overrides.clear()
    await engine.dispose()


async def test_nearby_empty_returns_empty_list(disc_client) -> None:
    client, _ = disc_client
    res = await client.get("/v1/discovery/nearby", params={"bbox": "35.5,51.2,35.85,51.6"})
    assert res.status_code == 200, res.text
    assert res.json() == []


async def test_contact_request_to_self_rejected(disc_client) -> None:
    client, state = disc_client
    me = state["user"].earth_id
    res = await client.post(f"/v1/discovery/{me}/contact-request", json={"message": "سلام"})
    assert res.status_code == 409, res.text


async def test_contact_request_unknown_target_404(disc_client) -> None:
    client, _ = disc_client
    res = await client.post(f"/v1/discovery/{uuid.uuid4()}/contact-request", json={"message": "سلام"})
    assert res.status_code == 404, res.text
