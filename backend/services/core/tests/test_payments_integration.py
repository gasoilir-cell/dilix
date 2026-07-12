"""تستِ یکپارچهٔ HTTP برای جریانِ escrow کیف پول (POST /v1/payments/...).

همان مسیری که صفحهٔ کیف پولِ وب اجرا می‌کند را از راهِ endpointها می‌آزماید:
ساختِ امانت → capture و مسیرِ جداگانهٔ refund، به‌علاوهٔ گاردِ IDOR روی capture
توسطِ کاربرِ غیرِ پرداخت‌کننده. engineِ مستقل با ATTACHِ schemaهای
`payments` و `events` (Outbox) — بدونِ دستکاریِ هارنسِ مشترکِ conftest.
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

_SCHEMAS = ("payments", "events")


# روی SQLite ستونِ JSONBِ Outbox را مثلِ JSON بساز (فقط برای تست).
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def pay_client():
    import app.modules.payments.models as _payments_models  # noqa: F401
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


def _escrow_body() -> dict:
    return {
        "payee_earth_id": str(uuid.uuid4()),
        "amount_minor": 50_000,
        "currency": "IRR",
        "provider_code": "sandbox",
    }


async def test_create_escrow_then_capture(pay_client) -> None:
    client, _ = pay_client
    res = await client.post("/v1/payments/escrow", json=_escrow_body())
    assert res.status_code == 201, res.text
    order = res.json()
    assert order["status"] == "escrowed"
    assert order["external_ref"]
    assert order["amount_minor"] == 50_000

    cap = await client.post(f"/v1/payments/{order['id']}/capture")
    assert cap.status_code == 200, cap.text
    assert cap.json()["status"] == "captured"


async def test_create_escrow_then_refund(pay_client) -> None:
    client, _ = pay_client
    order = (await client.post("/v1/payments/escrow", json=_escrow_body())).json()

    ref = await client.post(f"/v1/payments/{order['id']}/refund")
    assert ref.status_code == 200, ref.text
    assert ref.json()["status"] == "refunded"


async def test_capture_forbidden_for_non_payer(pay_client) -> None:
    client, state = pay_client
    order = (await client.post("/v1/payments/escrow", json=_escrow_body())).json()

    # کاربرِ دیگری (نه پرداخت‌کننده) نباید بتواند capture کند → گاردِ IDOR.
    state["user"] = type(state["user"])(earth_id=uuid.uuid4(), region="IR")
    res = await client.post(f"/v1/payments/{order['id']}/capture")
    assert res.status_code == 403, res.text
