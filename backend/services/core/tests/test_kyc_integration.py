"""تستِ یکپارچهٔ HTTP برای kyc (درخواستِ احرازِ هویت). schema: kyc."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("kyc",)
_MODELS = ("app.modules.kyc.models",)


@pytest_asyncio.fixture
async def kyc_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_submit_then_list(kyc_client) -> None:
    client, _ = kyc_client
    res = await client.post(
        "/v1/kyc/requests",
        json={"requested_level": 2, "documents": {"national_id": "doc-1"}},
    )
    assert res.status_code == 201, res.text
    req_id = res.json()["id"]
    assert res.json()["requested_level"] == 2

    listed = await client.get("/v1/kyc/requests")
    assert listed.status_code == 200, listed.text
    assert req_id in [r["id"] for r in listed.json()]


async def test_kyc_auth_required() -> None:
    await assert_auth_required("GET", "/v1/kyc/requests")
