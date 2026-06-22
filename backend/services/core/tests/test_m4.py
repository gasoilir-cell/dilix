"""تست‌های واحد M4 — MFA، Reputation، Marketplace، Realtime، i18n، GPS."""
from __future__ import annotations

import uuid
import pytest


# ── MFA ────────────────────────────────────────────────────────────────────────

def test_mfa_totp_roundtrip() -> None:
    """تولید TOTP secret و تأیید کد — pure function."""
    import pyotp
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    code = totp.now()
    assert totp.verify(code, valid_window=1)


def test_mfa_wrong_code_rejected() -> None:
    import pyotp
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    assert not totp.verify("000000", valid_window=1)


def test_mfa_setup_response_schema() -> None:
    from app.modules.auth.schemas import MfaSetupResponse
    resp = MfaSetupResponse(
        secret="JBSWY3DPEHPK3PXP",
        otpauth_uri="otpauth://totp/Dilix:test@example.com?secret=JBSWY3DPEHPK3PXP",
        qr_data_url=None,
    )
    assert resp.secret == "JBSWY3DPEHPK3PXP"
    assert "Dilix" in resp.otpauth_uri


# ── Device Keys (E2EE) ──────────────────────────────────────────────────────────

def test_device_key_schema() -> None:
    from app.modules.auth.schemas import DeviceKeyRegister
    key = DeviceKeyRegister(
        device_id="iPhone-16-Pro-ABC123",
        public_key="base64_encoded_x25519_public_key==",
        prekey_bundle={"signed_prekey": "...", "prekeys": []},
    )
    assert key.device_id == "iPhone-16-Pro-ABC123"
    assert key.prekey_bundle is not None


# ── Reputation ─────────────────────────────────────────────────────────────────

def test_reputation_normalize_rating() -> None:
    from app.modules.reputation.service import _normalize_rating
    assert _normalize_rating(1) == 0
    assert _normalize_rating(3) == 500
    assert _normalize_rating(5) == 1000


def test_reputation_score_ema() -> None:
    """شبیه‌سازی EMA امتیاز برای کاربر جدید (alpha=0.3)."""
    from app.modules.reputation.service import ALPHA_NEW, _normalize_rating
    score = 500  # امتیاز اولیه
    for rating in [5, 5, 4, 5]:
        normalized = _normalize_rating(rating)
        score = int(score * (1 - ALPHA_NEW) + normalized * ALPHA_NEW)
    assert score > 700, "امتیاز پس از چهار نقد مثبت باید بالا برود."


def test_reputation_review_schema() -> None:
    from app.modules.reputation.schemas import ReviewCreate
    eid = uuid.uuid4()
    review = ReviewCreate(
        reviewee_earth_id=eid,
        domain="logistics",
        transaction_ref=str(uuid.uuid4()),
        rating=5,
        comment="خیلی خوب بود",
    )
    assert review.rating == 5
    assert review.domain == "logistics"


# ── Marketplace ─────────────────────────────────────────────────────────────────

def test_marketplace_listing_schema() -> None:
    from app.modules.marketplace.schemas import ListingCreate
    listing = ListingCreate(
        title="طراحی لوگو حرفه‌ای",
        description="طراحی لوگو با فرمت وکتور و PNG در ۳ روز کاری",
        category="design",
        base_price_minor=5_000_000,
        currency="IRR",
        delivery_days=3,
        tags=["لوگو", "برند", "طراحی"],
    )
    assert listing.base_price_minor == 5_000_000
    assert "لوگو" in listing.tags


def test_marketplace_order_schema() -> None:
    from app.modules.marketplace.schemas import OrderCreate
    order = OrderCreate(
        listing_id=uuid.uuid4(),
        requirements="لوگو آبی رنگ با حروف اختصاری DX",
        agreed_price_minor=5_000_000,
        currency="IRR",
    )
    assert order.agreed_price_minor > 0


def test_marketplace_status_constants() -> None:
    from app.modules.marketplace.models import (
        ORDER_PENDING, ORDER_ACCEPTED, ORDER_DELIVERED, ORDER_COMPLETED,
        SERVICE_ACTIVE, SERVICE_PAUSED,
    )
    assert ORDER_PENDING != ORDER_COMPLETED
    assert SERVICE_ACTIVE != SERVICE_PAUSED


# ── GPS / FreightLocation ───────────────────────────────────────────────────────

def test_location_update_schema_validation() -> None:
    from app.modules.freight.schemas import LocationUpdate
    loc = LocationUpdate(latitude=35.6892, longitude=51.3890, speed_kmh=80.5)
    assert loc.latitude == 35.6892
    assert loc.speed_kmh == 80.5


def test_location_update_invalid_coords() -> None:
    from app.modules.freight.schemas import LocationUpdate
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        LocationUpdate(latitude=91.0, longitude=51.0)  # latitude > 90
    with pytest.raises(ValidationError):
        LocationUpdate(latitude=35.0, longitude=181.0)  # longitude > 180


# ── Realtime / WebSocket ────────────────────────────────────────────────────────

def test_ws_event_types() -> None:
    from app.modules.realtime.schemas import WsEventType
    assert WsEventType.PING == "ping"
    assert WsEventType.MESSAGE_NEW == "message.new"
    assert WsEventType.LOCATION_UPDATE == "location.update"


@pytest.mark.asyncio
async def test_connection_manager_online_count() -> None:
    """ConnectionManager: online_count و is_online بدون WebSocket واقعی."""
    from app.modules.realtime.connection_manager import ConnectionManager
    mgr = ConnectionManager()
    assert mgr.online_count == 0
    # تزریق مستقیم (بدون accept)
    class FakeWS:
        async def send_text(self, t): pass
    ws = FakeWS()
    mgr._connections["user-1"].add(ws)
    assert mgr.is_online("user-1")
    assert mgr.online_count == 1
    mgr._connections["user-1"].discard(ws)
    del mgr._connections["user-1"]
    assert not mgr.is_online("user-1")


# ── i18n ────────────────────────────────────────────────────────────────────────

def test_i18n_known_key() -> None:
    from app.core.i18n import t
    fa_text = t("error.not_found", locale="fa")
    en_text = t("error.not_found", locale="en")
    assert fa_text != en_text
    assert "یافت" in fa_text
    assert "not found" in en_text.lower()


def test_i18n_unknown_key_returns_key() -> None:
    from app.core.i18n import t
    assert t("nonexistent.key") == "nonexistent.key"


def test_i18n_unsupported_locale_fallback() -> None:
    from app.core.i18n import t
    # زبان ناشناخته → fallback به fa
    result = t("error.forbidden", locale="jp")
    assert "نیست" in result


# ── LangGraph Client ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_langgraph_stub_when_no_url() -> None:
    """وقتی AI_SERVICE_URL خالی است، stub محلی پاسخ می‌دهد."""
    from app.modules.ai.langgraph_client import invoke_agent, AGENT_PERSONAL
    reply = await invoke_agent(
        agent_type=AGENT_PERSONAL,
        conversation_id=str(uuid.uuid4()),
        earth_id=str(uuid.uuid4()),
        history=[],
        user_message="سلام، کمک می‌خواهم",
    )
    assert len(reply) > 10
    assert "PERSONAL" in reply or "دستیار" in reply


# ── Observability ─────────────────────────────────────────────────────────────────

def test_noop_tracer_does_not_crash() -> None:
    from app.core.observability import _NoopTracer
    tracer = _NoopTracer()
    with tracer.start_as_current_span("test-span"):
        pass  # نباید exception بدهد


def test_observability_disabled_by_default() -> None:
    from app.core.config import get_settings
    s = get_settings()
    assert not s.otel_enabled  # پیش‌فرض: خاموش
