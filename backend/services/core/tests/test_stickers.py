"""تست‌های واحدِ ماژول استیکر — اسکیماها، توابعِ کمکیِ روتر و ثبتِ مسیرها.

هم‌راستا با سبکِ سایرِ تست‌های Core: بدونِ دیتابیس/شبکه (جداولِ schema-qualified
روی SQLite قابلِ ساخت نیستند)، پس منطقِ mapping با ORMِ mock (SimpleNamespace)
و وجودِ endpointها از طریقِ `app.openapi()` بررسی می‌شود (ضدِ drift).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from types import SimpleNamespace


# ── اسکیماها ──────────────────────────────────────────────────────────────────
def test_pack_create_defaults() -> None:
    from app.modules.stickers.schemas import PackCreate

    body = PackCreate(title="ایموجی‌های من")
    assert body.title == "ایموجی‌های من"
    assert body.is_public is False
    assert body.description is None


def test_sticker_create_media_defaults_image() -> None:
    from app.modules.stickers.schemas import StickerCreate

    body = StickerCreate(media_url="https://cdn.example/s1.webp")
    assert body.media_type == "image"
    assert body.emoji_tag is None


def test_pack_detail_out_carries_stickers() -> None:
    from app.modules.stickers.schemas import PackDetailOut, StickerOut

    sid = uuid.uuid4()
    detail = PackDetailOut(
        id=uuid.uuid4(),
        owner_earth_id=uuid.uuid4(),
        title="پک",
        is_public=True,
        is_animated=False,
        is_mine=True,
        is_installed=False,
        install_count=0,
        sticker_count=1,
        created_at=datetime.now(timezone.utc),
        stickers=[
            StickerOut(
                id=sid,
                pack_id=uuid.uuid4(),
                media_url="u",
                media_type="image",
                created_at=datetime.now(timezone.utc),
            )
        ],
    )
    assert detail.stickers[0].id == sid


# ── توابعِ کمکیِ mapping (بدون DB) ────────────────────────────────────────────
def test_pack_out_flags_mine_and_installed() -> None:
    from app.modules.stickers.router import _pack_out

    me = uuid.uuid4()
    pid = uuid.uuid4()
    pack = SimpleNamespace(
        id=pid,
        owner_earth_id=me,
        title="من",
        description=None,
        cover_url=None,
        is_public=True,
        is_animated=False,
        install_count=3,
        sticker_count=2,
        created_at=datetime.now(timezone.utc),
    )
    out = _pack_out(pack, me, {pid})
    assert out.is_mine is True
    assert out.is_installed is True
    assert out.install_count == 3


def test_pack_out_not_mine_when_other_owner() -> None:
    from app.modules.stickers.router import _pack_out

    me = uuid.uuid4()
    pack = SimpleNamespace(
        id=uuid.uuid4(),
        owner_earth_id=uuid.uuid4(),
        title="دیگری",
        description="d",
        cover_url=None,
        is_public=True,
        is_animated=True,
        install_count=None,
        sticker_count=None,
        created_at=datetime.now(timezone.utc),
    )
    out = _pack_out(pack, me, set())
    assert out.is_mine is False
    assert out.is_installed is False
    assert out.install_count == 0  # None → 0
    assert out.sticker_count == 0


def test_sticker_out_starred_flag() -> None:
    from app.modules.stickers.router import _sticker_out

    sid = uuid.uuid4()
    s = SimpleNamespace(
        id=sid,
        pack_id=uuid.uuid4(),
        media_url="https://cdn/x.webp",
        media_type="image",
        emoji_tag="😀",
        title=None,
        created_at=datetime.now(timezone.utc),
    )
    assert _sticker_out(s, {sid}).is_starred is True
    assert _sticker_out(s, set()).is_starred is False


# ── ثبتِ مسیرها در اپ ─────────────────────────────────────────────────────────
def test_sticker_routes_registered() -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/v1/stickers/packs" in paths  # create
    assert "post" in paths["/v1/stickers/packs"]
    assert "/v1/stickers/packs/mine" in paths  # list mine
    assert "/v1/stickers/packs/public" in paths  # list public
    assert "/v1/stickers/packs/{pack_id}" in paths  # get detail
    assert "get" in paths["/v1/stickers/packs/{pack_id}"]
