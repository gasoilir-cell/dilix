"""تستِ یکپارچهٔ HTTP برای identity (Earth ID + پروفایل). schema: identity.

هویت هنگامِ ثبت‌نام (auth) ساخته می‌شود، نه با خواندنِ /me؛ بنابراین کاربرِ تازه
روی GET /me مقدارِ ۴۰۴ می‌گیرد. کاتالوگِ نقش‌ها ایستا و همیشه در دسترس است.
"""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("identity",)
_MODELS = ("app.modules.identity.models",)


@pytest_asyncio.fixture
async def identity_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_roles_catalog(identity_client) -> None:
    client, _ = identity_client
    res = await client.get("/v1/identity/roles")
    assert res.status_code == 200, res.text
    roles = res.json()
    assert isinstance(roles, list) and roles
    assert all("entity_type" in r for r in roles)


async def test_me_not_found_for_unregistered(identity_client) -> None:
    client, _ = identity_client
    res = await client.get("/v1/identity/me")
    assert res.status_code == 404, res.text


async def test_identity_auth_required() -> None:
    await assert_auth_required("GET", "/v1/identity/me")
