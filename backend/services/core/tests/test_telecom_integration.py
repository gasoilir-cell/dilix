"""تستِ یکپارچهٔ HTTP برای تلکام (POST /v1/telecom/top-up و /esim/activate).

جریانی که صفحهٔ وبِ telecom اجرا می‌کند: شارژ/بسته و فعال‌سازیِ eSIM. engineِ مستقل
با ATTACHِ schemaهای `telecom` و `events` (Outbox). ساختار دقیقاً مطابقِ
test_payments_integration.
"""
from __future__ import annotations

import uuid

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.pool import StaticPool

_SCHEMAS = ("telecom", "events")


# روی SQLite ستونِ JSONBِ Outbox را مثلِ JSON بساز (فقط برای تست).
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def tel_client():
    import app.modules.telecom.models as _telecom_models  # noqa: F401
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


async def test_top_up_creates_order(tel_client) -> None:
    client, _ = tel_client
    body = {
        "msisdn": "09121234567",
        "product_code": "DATA-5GB",
        "amount_minor": 500_000,
        "currency": "IRR",
        "provider_code": "sandbox",
    }
    res = await client.post("/v1/telecom/top-up", json=body)
    assert res.status_code == 201, res.text
    order = res.json()
    assert order["msisdn"] == "09121234567"
    assert order["product_code"] == "DATA-5GB"
    assert order["amount_minor"] == 500_000
    assert order["status"]


async def test_activate_esim_creates_profile(tel_client) -> None:
    client, _ = tel_client
    body = {
        "iccid": "8990011234567890123",
        "country_code": "IR",
        "provider_code": "sandbox",
    }
    res = await client.post("/v1/telecom/esim/activate", json=body)
    assert res.status_code == 201, res.text
    profile = res.json()
    assert profile["iccid"] == "8990011234567890123"
    assert profile["country_code"] == "IR"
    assert profile["status"]
