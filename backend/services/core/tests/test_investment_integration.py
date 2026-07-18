"""تستِ یکپارچهٔ HTTP برای investment (NAV + خرید واحد). schema: investment.

از آداپترِ ثبت‌شده‌ی «sandbox_fund» با NAVِ ثابتِ ۱٬۰۰۰٬۰۰۰ ریال استفاده می‌شود.
"""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("investment",)
_MODELS = ("app.modules.investment.models",)


@pytest_asyncio.fixture
async def inv_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_get_nav(inv_client) -> None:
    client, _ = inv_client
    res = await client.get("/v1/investment/nav", params={"fund_code": "DILIX_GROWTH"})
    assert res.status_code == 200, res.text
    assert res.json()["nav_minor"] == 1_000_000


async def test_buy_then_positions(inv_client) -> None:
    client, _ = inv_client
    buy = await client.post(
        "/v1/investment/buy",
        json={"fund_code": "DILIX_GROWTH", "amount_minor": 2_000_000},
    )
    assert buy.status_code == 201, buy.text
    pos_id = buy.json()["id"]
    assert buy.json()["units"] == 2.0

    positions = await client.get("/v1/investment/positions")
    assert positions.status_code == 200, positions.text
    assert pos_id in [p["id"] for p in positions.json()]


async def test_investment_auth_required() -> None:
    await assert_auth_required("GET", "/v1/investment/positions")
