"""تست‌های واحدِ ماژول داستان — اسکیماها، منطقِ دسترسی، انقضا و ثبتِ مسیرها.

هم‌راستا با سبکِ سایرِ تست‌های Core: بدونِ دیتابیس/شبکه؛ منطقِ `_can_view`،
انقضای ۲۴ساعته، اعتبارِ مخاطب‌ها و وجودِ endpointها از طریقِ `app.openapi()`.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone


# ── اسکیماها ──────────────────────────────────────────────────────────────────
def test_story_create_defaults() -> None:
    from app.modules.stories.schemas import StoryCreate

    body = StoryCreate(media_url="https://cdn.example/story.mp4")
    assert body.media_type == "image"
    assert body.audience == "public"
    assert body.caption is None


def test_circles_out_default_empty() -> None:
    from app.modules.stories.schemas import CirclesOut

    out = CirclesOut()
    assert out.colleagues == [] and out.family == [] and out.friends == []


# ── ثابت‌های مخاطب ────────────────────────────────────────────────────────────
def test_audiences_include_public_and_circles() -> None:
    from app.modules.stories.models import AUDIENCE_PUBLIC, AUDIENCES, CIRCLE_AUDIENCES

    assert AUDIENCE_PUBLIC == "public"
    assert set(CIRCLE_AUDIENCES) == {"colleagues", "family", "friends"}
    assert AUDIENCE_PUBLIC in AUDIENCES
    assert "followers" not in AUDIENCES  # مخاطبِ followers عمداً حذف شده


def test_story_expiry_is_24h() -> None:
    from app.modules.stories.models import _expiry

    delta = _expiry() - datetime.now(timezone.utc)
    assert timedelta(hours=23, minutes=59) < delta <= timedelta(hours=24, minutes=1)


# ── منطقِ دسترسی (_can_view) ─────────────────────────────────────────────────
def test_can_view_author_always() -> None:
    from app.modules.stories.router import _can_view

    me = uuid.uuid4()
    assert _can_view(me, "colleagues", me, set())  # نویسنده همیشه می‌بیند


def test_can_view_public() -> None:
    from app.modules.stories.router import _can_view

    author, me = uuid.uuid4(), uuid.uuid4()
    assert _can_view(author, "public", me, set())
    assert _can_view(author, "", me, set())  # خالی → public


def test_can_view_circle_requires_membership() -> None:
    from app.modules.stories.router import _can_view

    author, me = uuid.uuid4(), uuid.uuid4()
    assert not _can_view(author, "family", me, set())
    assert _can_view(author, "family", me, {(author, "family")})
    # عضویت در حلقه‌ی دیگر کافی نیست
    assert not _can_view(author, "family", me, {(author, "friends")})


def test_can_view_unknown_audience_denied() -> None:
    from app.modules.stories.router import _can_view

    author, me = uuid.uuid4(), uuid.uuid4()
    assert not _can_view(author, "followers", me, set())


# ── ثبتِ مسیرها در اپ ─────────────────────────────────────────────────────────
def test_story_routes_registered() -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/v1/stories" in paths  # create
    assert "post" in paths["/v1/stories"]
    assert "/v1/stories/feed" in paths  # list (rings)
    assert "/v1/stories/user/{earth_id}" in paths  # get by author
    assert "get" in paths["/v1/stories/user/{earth_id}"]
    assert "/v1/stories/circles" in paths
