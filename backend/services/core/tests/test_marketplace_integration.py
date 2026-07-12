"""تستِ یکپارچهٔ HTTP برای بازارگاه (POST/GET /v1/marketplace/listings).

جریانی که صفحهٔ وبِ marketplace اجرا می‌کند: ساختِ listing و سپس دیدنِ آن در
لیست/جستجو. engineِ مستقل با ATTACHِ schemaهای `marketplace` و `events` (Outbox) —
بدونِ دستکاریِ هارنسِ مشترکِ conftest. ساختار دقیقاً مطابقِ test_payments_integration.
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

_SCHEMAS = ("marketplace", "events")


# روی SQLite ستونِ JSONBِ Outbox را مثلِ JSON بساز (فقط برای تست).
@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def mk_client():
    import app.modules.marketplace.models as _marketplace_models  # noqa: F401
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


def _listing_body(title: str = "طراحیِ لوگوی حرفه‌ای", category: str = "design") -> dict:
    return {
        "title": title,
        "description": "طراحیِ لوگو و هویتِ بصری برای کسب‌وکارِ شما.",
        "category": category,
        "base_price_minor": 1_500_000,
        "currency": "IRR",
        "delivery_days": 5,
        "tags": ["logo", "brand"],
    }


async def test_create_listing_then_appears_in_list(mk_client) -> None:
    client, _ = mk_client
    res = await client.post("/v1/marketplace/listings", json=_listing_body())
    assert res.status_code == 201, res.text
    listing = res.json()
    assert listing["title"] == "طراحیِ لوگوی حرفه‌ای"
    assert listing["base_price_minor"] == 1_500_000

    lst = await client.get("/v1/marketplace/listings")
    assert lst.status_code == 200, lst.text
    ids = [item["id"] for item in lst.json()]
    assert listing["id"] in ids


async def test_search_by_category_filters(mk_client) -> None:
    client, _ = mk_client
    await client.post("/v1/marketplace/listings", json=_listing_body(title="ترجمهٔ متنِ تخصصی", category="translation"))
    await client.post("/v1/marketplace/listings", json=_listing_body(title="طراحیِ کارتِ ویزیت", category="design"))

    res = await client.get("/v1/marketplace/listings", params={"category": "translation"})
    assert res.status_code == 200, res.text
    cats = {item["category"] for item in res.json()}
    assert cats == {"translation"}
