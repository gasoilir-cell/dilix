"""تستِ یکپارچهٔ HTTP برای notification (صندوقِ پیام). schema: notification."""
from __future__ import annotations

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("notification",)
_MODELS = ("app.modules.notification.models",)


@pytest_asyncio.fixture
async def notif_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_empty_inbox_for_fresh_user(notif_client) -> None:
    client, _ = notif_client
    res = await client.get("/v1/notifications")
    assert res.status_code == 200, res.text
    assert res.json() == []


async def test_inbox_unread_only(notif_client) -> None:
    client, _ = notif_client
    res = await client.get("/v1/notifications", params={"unread_only": True})
    assert res.status_code == 200, res.text
    assert res.json() == []


async def test_notification_auth_required() -> None:
    await assert_auth_required("GET", "/v1/notifications")
