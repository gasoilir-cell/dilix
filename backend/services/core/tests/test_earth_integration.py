"""تستِ یکپارچهٔ HTTP برای earth (موقعیت + POI). schema: earth."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("earth",)
_MODELS = ("app.modules.earth.models",)


@pytest_asyncio.fixture
async def earth_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_update_location_then_get(earth_client) -> None:
    client, _ = earth_client
    body = {"lat": 35.7, "lon": 51.4, "geo_precision": "city", "is_visible": True}
    res = await client.put("/v1/earth/location", json=body)
    assert res.status_code == 200, res.text
    got = await client.get("/v1/earth/location")
    assert got.status_code == 200, got.text
    assert got.json()["is_visible"] is True


async def test_create_poi_then_nearby(earth_client) -> None:
    client, _ = earth_client
    body = {
        "name": "کافهٔ مرکزی",
        "category": "cafe",
        "lat": 35.72,
        "lon": 51.42,
        "country_code": "IR",
    }
    res = await client.post("/v1/earth/pois", json=body)
    assert res.status_code == 201, res.text
    poi_id = res.json()["id"]

    near = await client.get(
        "/v1/earth/pois", params={"lat": 35.72, "lon": 51.42, "radius_km": 5}
    )
    assert near.status_code == 200, near.text
    assert poi_id in [p["id"] for p in near.json()]


async def test_earth_auth_required() -> None:
    await assert_auth_required("GET", "/v1/earth/location")
