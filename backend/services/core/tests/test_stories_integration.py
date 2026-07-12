"""تست‌های یکپارچهٔ endpointهای داستان — روی SQLite درون‌حافظه‌ای (هارنسِ conftest).

مسیرهای اصلی (create/feed/user/view/viewers) + حلقه‌های مخاطب، happy-path واقعی با DB.
"""
from __future__ import annotations

import uuid


async def _create_story(integration, audience="public", caption=None) -> dict:
    body = {"media_url": "https://cdn/story.jpg", "media_type": "image", "audience": audience}
    if caption:
        body["caption"] = caption
    r = await integration.client.post("/v1/stories", json=body)
    assert r.status_code == 201, r.text
    return r.json()


async def test_create_story_is_mine(integration) -> None:
    story = await _create_story(integration, caption="سلام")
    assert story["is_mine"] is True
    assert story["audience"] == "public"
    assert story["view_count"] == 0
    assert story["caption"] == "سلام"


async def test_feed_shows_own_ring(integration) -> None:
    await _create_story(integration)
    r = await integration.client.get("/v1/stories/feed")
    assert r.status_code == 200
    rings = r.json()
    me = str(integration.earth_id)
    mine = [ring for ring in rings if ring["author_earth_id"] == me]
    assert mine and mine[0]["is_me"] is True
    assert mine[0]["story_count"] == 1


async def test_user_stories_by_author(integration) -> None:
    author = integration.earth_id
    story = await _create_story(integration)
    r = await integration.client.get(f"/v1/stories/user/{author}")
    assert r.status_code == 200
    stories = r.json()
    assert [s["id"] for s in stories] == [story["id"]]
    assert stories[0]["is_mine"] is True


async def test_view_and_viewers_flow(integration) -> None:
    author = integration.earth_id
    story = await _create_story(integration)  # public

    # کاربر دیگری آن را می‌بیند
    viewer = integration.as_user()
    r = await integration.client.post(f"/v1/stories/{story['id']}/view")
    assert r.status_code == 204
    # idempotent: بازدیدِ دوباره باز هم ۲۰۴ و بدونِ افزایشِ تکراری
    r = await integration.client.post(f"/v1/stories/{story['id']}/view")
    assert r.status_code == 204

    # نویسنده لیستِ بازدیدکنندگان را می‌بیند
    integration.as_user(earth_id=author)
    r = await integration.client.get(f"/v1/stories/{story['id']}/viewers")
    assert r.status_code == 200
    viewers = r.json()
    assert [v["viewer_earth_id"] for v in viewers] == [str(viewer)]


async def test_viewers_forbidden_for_non_author(integration) -> None:
    story = await _create_story(integration)
    integration.as_user()  # کاربر دیگر
    r = await integration.client.get(f"/v1/stories/{story['id']}/viewers")
    assert r.status_code == 403


async def test_private_circle_story_hidden_then_visible(integration) -> None:
    author = integration.earth_id
    # مخاطبِ داستان: حلقهٔ family
    story = await _create_story(integration, audience="family")

    # عضوی که در حلقه نیست، در feed آن را نمی‌بیند
    outsider = integration.as_user()
    r = await integration.client.get("/v1/stories/feed")
    assert str(author) not in [ring["author_earth_id"] for ring in r.json()]

    # نویسنده outsider را به حلقهٔ family اضافه می‌کند
    integration.as_user(earth_id=author)
    r = await integration.client.post(
        "/v1/stories/circles/family", json={"earth_id": str(outsider)}
    )
    assert r.status_code == 201, r.text

    # حالا outsider داستان را در feed می‌بیند
    integration.as_user(earth_id=outsider)
    r = await integration.client.get("/v1/stories/feed")
    assert str(author) in [ring["author_earth_id"] for ring in r.json()]


async def test_circles_list_and_add(integration) -> None:
    member = uuid.uuid4()
    r = await integration.client.post(
        "/v1/stories/circles/friends", json={"earth_id": str(member)}
    )
    assert r.status_code == 201

    r = await integration.client.get("/v1/stories/circles")
    assert r.status_code == 200
    circles = r.json()
    assert str(member) in [m["earth_id"] for m in circles["friends"]]
    assert circles["family"] == []


async def test_add_self_to_circle_rejected(integration) -> None:
    r = await integration.client.post(
        "/v1/stories/circles/friends", json={"earth_id": str(integration.earth_id)}
    )
    assert r.status_code == 400
