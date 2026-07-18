"""تستِ یکپارچهٔ HTTP برای freight (بار + پیشنهاد). schema: freight."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("freight",)
_MODELS = ("app.modules.freight.models",)


@pytest_asyncio.fixture
async def freight_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_post_cargo_then_list(freight_client) -> None:
    client, _ = freight_client
    body = {
        "title": "بارِ تهران به مشهد",
        "origin": "تهران",
        "destination": "مشهد",
        "weight_grams": 500_000,
        "budget_minor": 3_000_000,
    }
    res = await client.post("/v1/freight/cargo", json=body)
    assert res.status_code == 201, res.text
    cargo_id = res.json()["id"]
    assert res.json()["status"] == "open"

    listed = await client.get("/v1/freight/cargo")
    assert listed.status_code == 200, listed.text
    assert cargo_id in [c["id"] for c in listed.json()]


async def test_new_cargo_has_no_bids(freight_client) -> None:
    client, _ = freight_client
    res = await client.post(
        "/v1/freight/cargo",
        json={
            "title": "محموله",
            "origin": "اصفهان",
            "destination": "شیراز",
            "weight_grams": 100_000,
        },
    )
    cargo_id = res.json()["id"]
    bids = await client.get(f"/v1/freight/cargo/{cargo_id}/bids")
    assert bids.status_code == 200, bids.text
    assert bids.json() == []


async def test_freight_auth_required() -> None:
    await assert_auth_required("GET", "/v1/freight/cargo")
