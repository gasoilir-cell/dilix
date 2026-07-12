"""تستِ یکپارچهٔ HTTP برای Growth (GET /v1/growth/...).

سه اندپوینتِ خواندنیِ صفحهٔ وبِ growth را برای کاربرِ تازه (بدونِ داده) می‌آزماید:
لینکِ دعوت، کیفِ پاداش، و سهمِ درآمد. engineِ مستقل با ATTACHِ schemaهای
`referral`/`membership`/`investment` — بدونِ دستکاریِ هارنسِ مشترکِ conftest.
ساختار مطابقِ test_telecom_integration.
"""
from __future__ import annotations

import uuid

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

_SCHEMAS = ("referral", "membership", "investment")


@pytest_asyncio.fixture
async def growth_client():
    import app.modules.referral.models as _referral_models  # noqa: F401
    import app.modules.membership.models as _membership_models  # noqa: F401
    import app.modules.investment.models as _investment_models  # noqa: F401
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


async def test_referral_link_for_fresh_user(growth_client) -> None:
    client, _ = growth_client
    res = await client.get("/v1/growth/referrals/link")
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["code"]
    assert body["url"].endswith(body["code"])
    assert body["total_referred"] == 0


async def test_rewards_empty_for_fresh_user(growth_client) -> None:
    client, _ = growth_client
    res = await client.get("/v1/growth/rewards")
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["balances"] == []
    assert body["pending_count"] == 0


async def test_revenue_share_free_plan_not_eligible(growth_client) -> None:
    client, _ = growth_client
    res = await client.get("/v1/growth/revenue-share")
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["eligible"] is False
    assert body["entitlement_bps"] == 0
    assert body["investment_units"] == 0
