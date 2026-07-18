"""تستِ یکپارچهٔ HTTP برای referral (ثبتِ زنجیرهٔ دعوت). schema: referral."""
from __future__ import annotations

import uuid

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("referral",)
_MODELS = ("app.modules.referral.models",)


@pytest_asyncio.fixture
async def ref_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_register_referral(ref_client) -> None:
    client, _ = ref_client
    referrer = str(uuid.uuid4())
    res = await client.post("/v1/referral/register", json={"referrer_earth_id": referrer})
    assert res.status_code == 201, res.text
    referrals = res.json()
    assert isinstance(referrals, list) and referrals
    assert referrals[0]["referrer_earth_id"] == referrer


async def test_duplicate_register_conflicts(ref_client) -> None:
    client, _ = ref_client
    referrer = str(uuid.uuid4())
    first = await client.post("/v1/referral/register", json={"referrer_earth_id": referrer})
    assert first.status_code == 201, first.text
    dup = await client.post("/v1/referral/register", json={"referrer_earth_id": referrer})
    assert dup.status_code == 409, dup.text


async def test_referral_auth_required() -> None:
    await assert_auth_required("POST", "/v1/referral/register")
