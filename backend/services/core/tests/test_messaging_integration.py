"""تستِ یکپارچهٔ HTTP برای پیام‌رسان — به‌ویژه `GET /v1/messaging/rooms`.

جریانی که کلاینت‌های موبایل/وب اجرا می‌کنند: کاربر اتاق می‌سازد و سپس فهرستِ
اتاق‌های خودش را می‌بیند. تأیید می‌کنیم که فهرست فقط اتاق‌هایی را برمی‌گرداند که
کاربر عضوِ آن‌هاست (نه اتاقِ کاربرِ دیگر) و مرتب‌سازی بر اساسِ جدیدترین فعالیت است.
engineِ مستقل با ATTACHِ schemaهای `messaging` و `events` (Outbox) — ساختار مطابقِ
test_marketplace_integration.
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

_SCHEMAS = ("messaging", "events")


@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def mg_client():
    import app.modules.messaging.models as _messaging_models  # noqa: F401
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


def _set_user(state: dict, uid: uuid.UUID) -> None:
    from app.modules.auth.deps import CurrentUser

    state["user"] = CurrentUser(earth_id=uid, region="IR")


async def _make_room(client: AsyncClient, title: str) -> str:
    res = await client.post(
        "/v1/messaging/rooms", json={"room_type": "group", "title": title}
    )
    assert res.status_code == 201, res.text
    return res.json()["id"]


async def test_list_rooms_returns_only_my_rooms(mg_client) -> None:
    client, state = mg_client
    user_a = uuid.uuid4()
    user_b = uuid.uuid4()

    # کاربر A دو اتاق می‌سازد
    _set_user(state, user_a)
    room_a1 = await _make_room(client, "اتاقِ A-1")
    room_a2 = await _make_room(client, "اتاقِ A-2")

    # کاربر B یک اتاقِ جدا می‌سازد
    _set_user(state, user_b)
    room_b1 = await _make_room(client, "اتاقِ B-1")

    # فهرستِ B فقط اتاقِ خودش را دارد
    res_b = await client.get("/v1/messaging/rooms")
    assert res_b.status_code == 200, res_b.text
    assert {r["id"] for r in res_b.json()} == {room_b1}

    # فهرستِ A هر دو اتاقِ A را دارد و اتاقِ B را نه
    _set_user(state, user_a)
    res_a = await client.get("/v1/messaging/rooms")
    assert res_a.status_code == 200, res_a.text
    ids_a = {r["id"] for r in res_a.json()}
    assert ids_a == {room_a1, room_a2}
    assert room_b1 not in ids_a


async def test_list_rooms_orders_by_latest_activity(mg_client) -> None:
    client, state = mg_client
    _set_user(state, uuid.uuid4())

    room_1 = await _make_room(client, "اتاقِ ۱")
    room_2 = await _make_room(client, "اتاقِ ۲")

    # پیامِ جدید در اتاقِ ۱ → باید به بالای فهرست بیاید
    send = await client.post(
        f"/v1/messaging/rooms/{room_1}/messages", json={"content": "سلام"}
    )
    assert send.status_code == 201, send.text

    res = await client.get("/v1/messaging/rooms")
    assert res.status_code == 200, res.text
    ordered = [r["id"] for r in res.json()]
    assert ordered[0] == room_1
    assert set(ordered) == {room_1, room_2}
