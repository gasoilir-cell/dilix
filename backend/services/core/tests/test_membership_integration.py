"""تستِ یکپارچهٔ HTTP برای membership (اشتراک). schema: membership.

GET برای کاربرِ تازه به‌صورتِ خودکار اشتراکِ رایگانِ پیش‌فرض می‌سازد.
"""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("membership",)
_MODELS = ("app.modules.membership.models",)


@pytest_asyncio.fixture
async def mem_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_get_creates_free_default(mem_client) -> None:
    client, _ = mem_client
    res = await client.get("/v1/membership")
    assert res.status_code == 200, res.text
    assert res.json()["plan"] == "free"


async def test_upgrade_then_cancel(mem_client) -> None:
    client, _ = mem_client
    up = await client.post("/v1/membership/upgrade", json={"plan": "standard", "months": 3})
    assert up.status_code == 200, up.text
    assert up.json()["plan"] == "standard"

    cancel = await client.post("/v1/membership/cancel")
    assert cancel.status_code == 200, cancel.text


async def test_membership_auth_required() -> None:
    await assert_auth_required("GET", "/v1/membership")
