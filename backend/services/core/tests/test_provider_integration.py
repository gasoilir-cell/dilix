"""تستِ یکپارچهٔ HTTP برای provider (ثبتِ ارائه‌دهنده + API). schema: provider."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("provider",)
_MODELS = ("app.modules.provider.models",)


@pytest_asyncio.fixture
async def prov_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_register_then_add_api(prov_client) -> None:
    client, _ = prov_client
    reg = await client.post(
        "/v1/providers/register",
        json={"legal_name": "بیمهٔ نمونه", "provider_type": "insurer"},
    )
    assert reg.status_code == 201, reg.text
    provider_id = reg.json()["id"]

    api = await client.post(
        f"/v1/providers/{provider_id}/apis",
        json={"name": "quote-api", "spec_url": "https://example.test/openapi.json"},
    )
    assert api.status_code == 201, api.text
    api_id = api.json()["id"]

    listed = await client.get(f"/v1/providers/{provider_id}/apis")
    assert listed.status_code == 200, listed.text
    assert api_id in [a["id"] for a in listed.json()]


async def test_provider_auth_required() -> None:
    await assert_auth_required(
        "POST", "/v1/providers/register"
    )


async def test_provider_credential_returns_raw_key(prov_client) -> None:
    client, _ = prov_client
    reg = await client.post(
        "/v1/providers/register",
        json={"legal_name": "کریرِ نمونه", "provider_type": "carrier"},
    )
    provider_id = reg.json()["id"]
    cred = await client.post(
        f"/v1/providers/{provider_id}/credentials", json={"env": "sandbox"}
    )
    assert cred.status_code == 201, cred.text
    assert cred.json()["api_key"]
    assert cred.json()["env"] == "sandbox"
