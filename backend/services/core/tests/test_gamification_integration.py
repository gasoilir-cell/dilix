"""تستِ یکپارچهٔ HTTP برای gamification (امتیاز + نشان). schema: gamification."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("gamification",)
_MODELS = ("app.modules.gamification.models",)


@pytest_asyncio.fixture
async def gami_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_fresh_user_zero_points(gami_client) -> None:
    client, _ = gami_client
    res = await client.get("/v1/gamification/points")
    assert res.status_code == 200, res.text
    assert res.json()["balance"] == 0


async def test_fresh_user_no_badges(gami_client) -> None:
    client, _ = gami_client
    res = await client.get("/v1/gamification/badges")
    assert res.status_code == 200, res.text
    assert res.json() == []


async def test_gamification_auth_required() -> None:
    await assert_auth_required("GET", "/v1/gamification/points")
