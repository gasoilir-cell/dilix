"""تستِ یکپارچهٔ HTTP برای فیلترِ ریلز — `GET /v1/social/feed?post_type=reel`.

جریانی که کلاینتِ ریلز (وب/موبایل) اجرا می‌کند: کاربر A کاربر B را فالو می‌کند،
B چند پست از نوع‌های مختلف (reel، text، video) منتشر می‌کند، و A فیدِ خود را با
`post_type=reel` می‌گیرد. تأیید می‌کنیم که فقط پست‌های `reel` برگردانده می‌شوند و
فیدِ بدونِ فیلتر همهٔ پست‌ها را دارد. engineِ مستقل با ATTACHِ schemaهای `social` و
`events` (Outbox) — ساختار مطابقِ test_messaging_integration.
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

_SCHEMAS = ("social", "events")


@compiles(JSONB, "sqlite")
def _compile_jsonb_sqlite(element, compiler, **kw):  # noqa: ANN001, ANN201
    return "JSON"


@pytest_asyncio.fixture
async def sc_client():
    import app.modules.social.models as _social_models  # noqa: F401
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


async def _create_post(client: AsyncClient, post_type: str, content: str) -> str:
    res = await client.post(
        "/v1/social/posts", json={"post_type": post_type, "content": content}
    )
    assert res.status_code == 201, res.text
    return res.json()["id"]


async def test_feed_reel_filter_returns_only_reels(sc_client) -> None:
    client, state = sc_client
    viewer = uuid.uuid4()
    author = uuid.uuid4()

    # نویسنده سه پست از نوع‌های مختلف منتشر می‌کند
    _set_user(state, author)
    reel_1 = await _create_post(client, "reel", "ریلِ اول")
    reel_2 = await _create_post(client, "reel", "ریلِ دوم")
    await _create_post(client, "text", "یک متنِ ساده")
    await _create_post(client, "video", "ویدیوی معمولی")

    # بیننده نویسنده را فالو می‌کند
    _set_user(state, viewer)
    follow = await client.post(f"/v1/social/follow/{author}")
    assert follow.status_code == 204, follow.text

    # فیدِ فیلترشده فقط ریل‌ها را دارد
    res = await client.get("/v1/social/feed?post_type=reel")
    assert res.status_code == 200, res.text
    body = res.json()
    ids = {p["id"] for p in body}
    assert ids == {reel_1, reel_2}
    assert all(p["post_type"] == "reel" for p in body)

    # فیدِ بدونِ فیلتر همهٔ چهار پست را دارد
    res_all = await client.get("/v1/social/feed")
    assert res_all.status_code == 200, res_all.text
    assert len(res_all.json()) == 4


async def test_feed_reel_filter_empty_when_no_reels(sc_client) -> None:
    client, state = sc_client
    viewer = uuid.uuid4()
    author = uuid.uuid4()

    _set_user(state, author)
    await _create_post(client, "text", "فقط متن")

    _set_user(state, viewer)
    follow = await client.post(f"/v1/social/follow/{author}")
    assert follow.status_code == 204, follow.text

    res = await client.get("/v1/social/feed?post_type=reel")
    assert res.status_code == 200, res.text
    assert res.json() == []
