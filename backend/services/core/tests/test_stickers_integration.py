"""تست‌های یکپارچهٔ endpointهای استیکر — روی SQLite درون‌حافظه‌ای (هارنسِ conftest).

مسیرهای اصلی (create/list/get) + چرخهٔ نصب و ستاره، happy-path واقعی با DB.
"""
from __future__ import annotations

import uuid


async def _create_pack(integration, title="پک تست", is_public=True) -> dict:
    r = await integration.client.post(
        "/v1/stickers/packs", json={"title": title, "is_public": is_public}
    )
    assert r.status_code == 201, r.text
    return r.json()


async def _add_sticker(integration, pack_id, media_url="https://cdn/x.webp") -> dict:
    r = await integration.client.post(
        f"/v1/stickers/packs/{pack_id}/stickers",
        json={"media_url": media_url, "media_type": "image", "emoji_tag": "😀"},
    )
    assert r.status_code == 201, r.text
    return r.json()


async def test_create_pack_returns_mine(integration) -> None:
    pack = await _create_pack(integration, title="ایموجی‌های من")
    assert pack["title"] == "ایموجی‌های من"
    assert pack["is_mine"] is True
    assert pack["is_installed"] is False
    assert pack["sticker_count"] == 0


async def test_list_mine_includes_created(integration) -> None:
    pack = await _create_pack(integration)
    r = await integration.client.get("/v1/stickers/packs/mine")
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert pack["id"] in ids


async def test_add_sticker_and_get_detail(integration) -> None:
    pack = await _create_pack(integration)
    sticker = await _add_sticker(integration, pack["id"])
    assert sticker["pack_id"] == pack["id"]

    r = await integration.client.get(f"/v1/stickers/packs/{pack['id']}")
    assert r.status_code == 200
    detail = r.json()
    assert detail["sticker_count"] == 1
    assert len(detail["stickers"]) == 1
    assert detail["stickers"][0]["id"] == sticker["id"]
    # افزودنِ استیکر، cover را از خالی پر می‌کند
    assert detail["cover_url"] == "https://cdn/x.webp"


async def test_public_listing_shows_public_pack_with_stickers(integration) -> None:
    pack = await _create_pack(integration, title="عمومی", is_public=True)
    await _add_sticker(integration, pack["id"])  # sticker_count>0 لازم است

    r = await integration.client.get("/v1/stickers/packs/public")
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert pack["id"] in ids


async def test_private_pack_hidden_from_public(integration) -> None:
    pack = await _create_pack(integration, title="خصوصی", is_public=False)
    await _add_sticker(integration, pack["id"])
    r = await integration.client.get("/v1/stickers/packs/public")
    assert pack["id"] not in [p["id"] for p in r.json()]


async def test_install_flow_by_other_user(integration) -> None:
    # کاربر A یک بستهٔ عمومی با استیکر می‌سازد
    pack = await _create_pack(integration, title="اشتراکی", is_public=True)
    await _add_sticker(integration, pack["id"])

    # کاربر B نصب می‌کند
    integration.as_user()
    r = await integration.client.post(f"/v1/stickers/packs/{pack['id']}/install")
    assert r.status_code == 204

    r = await integration.client.get("/v1/stickers/packs/installed")
    assert r.status_code == 200
    listed = r.json()
    assert pack["id"] in [p["id"] for p in listed]
    assert listed[0]["is_installed"] is True
    assert listed[0]["is_mine"] is False


async def test_star_and_starred_listing(integration) -> None:
    pack = await _create_pack(integration)
    sticker = await _add_sticker(integration, pack["id"])

    r = await integration.client.post(f"/v1/stickers/{sticker['id']}/star")
    assert r.status_code == 204

    r = await integration.client.get("/v1/stickers/starred")
    assert r.status_code == 200
    starred = r.json()
    assert sticker["id"] in [s["id"] for s in starred]
    assert starred[0]["is_starred"] is True


async def test_delete_sticker_then_pack(integration) -> None:
    pack = await _create_pack(integration)
    sticker = await _add_sticker(integration, pack["id"])

    r = await integration.client.delete(f"/v1/stickers/{sticker['id']}")
    assert r.status_code == 204
    r = await integration.client.get(f"/v1/stickers/packs/{pack['id']}")
    assert r.status_code == 200
    detail = r.json()
    assert detail["sticker_count"] == 0
    assert detail["stickers"] == []

    r = await integration.client.delete(f"/v1/stickers/packs/{pack['id']}")
    assert r.status_code == 204
    r = await integration.client.get(f"/v1/stickers/packs/{pack['id']}")
    assert r.status_code == 404


async def test_delete_pack_forbidden_to_other_user_as_404(integration) -> None:
    pack = await _create_pack(integration, is_public=False)
    integration.as_user()
    r = await integration.client.delete(f"/v1/stickers/packs/{pack['id']}")
    assert r.status_code == 404


async def test_stickers_auth_required_for_protected_routes() -> None:
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/v1/stickers/packs/mine")
    assert r.status_code == 403


async def test_get_unknown_pack_404(integration) -> None:
    r = await integration.client.get(f"/v1/stickers/packs/{uuid.uuid4()}")
    assert r.status_code == 404
