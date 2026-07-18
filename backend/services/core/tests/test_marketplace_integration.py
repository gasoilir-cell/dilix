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


# ─────────── چرخهٔ کاملِ سفارش (escrow → complete) ───────────
# این جریان علاوه بر marketplace به schemaِ `payments` (سفارشِ امانی) هم نیاز دارد.
_ORDER_SCHEMAS = ("marketplace", "payments", "events")


def _set_user(state: dict, uid: uuid.UUID) -> None:
    from app.modules.auth.deps import CurrentUser

    state["user"] = CurrentUser(earth_id=uid, region="IR")


@pytest_asyncio.fixture
async def mk_order_client():
    import app.modules.marketplace.models as _marketplace_models  # noqa: F401
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
        for name in _ORDER_SCHEMAS:
            cur.execute(f"ATTACH DATABASE ':memory:' AS {name}")
        cur.close()

    tables = [t for t in Base.metadata.sorted_tables if t.schema in _ORDER_SCHEMAS]
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


async def test_full_order_flow_and_my_orders_scope(mk_order_client) -> None:
    client, state = mk_order_client
    provider = uuid.uuid4()
    buyer = uuid.uuid4()
    stranger = uuid.uuid4()

    # ارائه‌دهنده یک آگهی می‌سازد
    _set_user(state, provider)
    res = await client.post("/v1/marketplace/listings", json=_listing_body())
    assert res.status_code == 201, res.text
    listing_id = res.json()["id"]

    # خریدار سفارش می‌دهد (escrow ساخته می‌شود)
    _set_user(state, buyer)
    place = await client.post(
        "/v1/marketplace/orders",
        json={"listing_id": listing_id, "agreed_price_minor": 1_500_000, "currency": "IRR"},
    )
    assert place.status_code == 201, place.text
    order = place.json()
    order_id = order["id"]
    assert order["status"] == "pending"
    assert order["payment_order_id"] is not None

    # ارائه‌دهنده accept و سپس deliver می‌کند
    _set_user(state, provider)
    acc = await client.post(f"/v1/marketplace/orders/{order_id}/accept")
    assert acc.status_code == 200, acc.text
    assert acc.json()["status"] == "accepted"

    dlv = await client.post(f"/v1/marketplace/orders/{order_id}/deliver")
    assert dlv.status_code == 200, dlv.text
    assert dlv.json()["status"] == "delivered"

    # خریدار تحویل را تأیید می‌کند → escrow آزاد و سفارش completed
    _set_user(state, buyer)
    done = await client.post(f"/v1/marketplace/orders/{order_id}/complete")
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "completed"

    # «سفارش‌های من»: هم خریدار و هم فروشنده سفارش را می‌بینند
    my_buyer = await client.get("/v1/marketplace/orders")
    assert my_buyer.status_code == 200, my_buyer.text
    assert {o["id"] for o in my_buyer.json()} == {order_id}

    _set_user(state, provider)
    my_provider = await client.get("/v1/marketplace/orders")
    assert my_provider.status_code == 200, my_provider.text
    assert {o["id"] for o in my_provider.json()} == {order_id}

    # کاربرِ بی‌ربط هیچ سفارشی نمی‌بیند
    _set_user(state, stranger)
    none = await client.get("/v1/marketplace/orders")
    assert none.status_code == 200, none.text
    assert none.json() == []
