"""تست‌های واحدِ M3 — ماژول‌های جدید (بدونِ DB/NATS)."""
from __future__ import annotations

import pytest
from dilix_shared.adapter import AdapterError


# ── KYC ──────────────────────────────────────────────────────────────────────

def test_kyc_status_constants_present() -> None:
    from app.modules.kyc.models import (
        STATUS_APPROVED, STATUS_IN_REVIEW, STATUS_PENDING, STATUS_REJECTED,
    )
    assert STATUS_PENDING != STATUS_APPROVED
    assert STATUS_REJECTED != STATUS_IN_REVIEW


# ── Freight State Machine ─────────────────────────────────────────────────────

def test_freight_state_machine() -> None:
    from app.modules.freight.models import (
        CARGO_ASSIGNED, CARGO_BIDDING, CARGO_CANCELLED,
        CARGO_DELIVERED, CARGO_IN_TRANSIT, CARGO_OPEN, CARGO_SETTLED,
    )
    from app.modules.freight.state import can_transition, is_terminal

    assert can_transition(CARGO_OPEN, CARGO_BIDDING)
    assert can_transition(CARGO_BIDDING, CARGO_ASSIGNED)
    assert can_transition(CARGO_ASSIGNED, CARGO_IN_TRANSIT)
    assert can_transition(CARGO_IN_TRANSIT, CARGO_DELIVERED)
    assert can_transition(CARGO_DELIVERED, CARGO_SETTLED)
    # گذارِ نامعتبر: open مستقیم به delivered
    assert not can_transition(CARGO_OPEN, CARGO_DELIVERED)
    # نهایی
    assert is_terminal(CARGO_SETTLED)
    assert is_terminal(CARGO_CANCELLED)
    assert not is_terminal(CARGO_OPEN)


# ── Telecom Sandbox Adapter ───────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_telecom_top_up_sandbox() -> None:
    from app.modules.telecom.adapters.sandbox import SandboxTelecomAdapter
    from app.modules.telecom.ports import TopUpRequest

    adapter = SandboxTelecomAdapter()
    result = await adapter.top_up(
        TopUpRequest(subscriber_ref="u", msisdn="09123456789",
                     amount_minor=500_000, currency="IRR", product_code="1GB")
    )
    assert result.status == "success"
    assert result.external_ref.startswith("tu_")


@pytest.mark.asyncio
async def test_telecom_esim_invalid_iccid() -> None:
    from app.modules.telecom.adapters.sandbox import SandboxTelecomAdapter
    from app.modules.telecom.ports import EsimActivationRequest

    adapter = SandboxTelecomAdapter()
    with pytest.raises(AdapterError):
        await adapter.activate_esim(
            EsimActivationRequest(subscriber_ref="u", iccid="short", country_code="IR")
        )


# ── Investment Sandbox Adapter ────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_investment_buy_and_sell_sandbox() -> None:
    from app.modules.investment.adapters.sandbox import SandboxInvestmentAdapter
    from app.modules.investment.ports import UnitBuyRequest, UnitSellRequest

    adapter = SandboxInvestmentAdapter()
    buy = await adapter.buy_units(
        UnitBuyRequest(investor_ref="u", fund_code="GOLD", amount_minor=5_000_000, currency="IRR")
    )
    assert buy.status == "executed"
    assert buy.units == 5.0  # 5_000_000 / 1_000_000

    sell = await adapter.sell_units(
        UnitSellRequest(investor_ref="u", position_ref="p", units=2.0)
    )
    assert sell.status == "executed"


@pytest.mark.asyncio
async def test_investment_min_amount() -> None:
    from app.modules.investment.adapters.sandbox import SandboxInvestmentAdapter
    from app.modules.investment.ports import UnitBuyRequest

    adapter = SandboxInvestmentAdapter()
    with pytest.raises(AdapterError):
        await adapter.buy_units(
            UnitBuyRequest(investor_ref="u", fund_code="X", amount_minor=100, currency="IRR")
        )


# ── Gamification ─────────────────────────────────────────────────────────────

def test_gamification_plan_cashback() -> None:
    from app.modules.membership.models import PLAN_CASHBACK_BPS, PLAN_PREMIUM, PLAN_STANDARD
    assert PLAN_CASHBACK_BPS[PLAN_STANDARD] == 100
    assert PLAN_CASHBACK_BPS[PLAN_PREMIUM] == 250


# ── Referral anti-pyramid invariant ─────────────────────────────────────────

def test_referral_max_levels_constant() -> None:
    from app.modules.referral.models import MAX_REFERRAL_LEVELS
    assert MAX_REFERRAL_LEVELS == 3


# ── Earth location fuzzing ────────────────────────────────────────────────────

def test_earth_fuzz_exact_unchanged() -> None:
    from app.modules.earth.service import _fuzz
    lat, lon = 35.7, 51.4
    fl, fo = _fuzz(lat, lon, "exact")
    assert fl == lat and fo == lon


def test_earth_fuzz_region_differs() -> None:
    import random
    random.seed(42)
    from app.modules.earth.service import _fuzz
    lat, lon = 35.7, 51.4
    fl, fo = _fuzz(lat, lon, "region")
    # region fuzz باید تفاوتی ایجاد کند
    assert fl != lat or fo != lon


# ── AI stub ──────────────────────────────────────────────────────────────────

def test_ai_stub_reply_contains_agent_type() -> None:
    # _stub_reply به langgraph_client منتقل شده
    from app.modules.ai.langgraph_client import _local_stub
    reply = _local_stub("freight", "بار دارم")
    assert "FREIGHT" in reply


# ── Authorization policy — نقش‌های جدید ─────────────────────────────────────

def test_policy_covers_new_roles() -> None:
    from app.modules.authorization.policy import ROLE_PERMISSIONS
    assert "driver" in ROLE_PERMISSIONS
    assert "logistics" in ROLE_PERMISSIONS
    assert "moderator" in ROLE_PERMISSIONS
    assert "regional_admin" in ROLE_PERMISSIONS
    # driver باید freight.place_bid داشته باشد
    assert "freight.place_bid" in ROLE_PERMISSIONS["driver"]
    # cargo_owner باید earth.create_poi داشته باشد
    assert "earth.create_poi" in ROLE_PERMISSIONS["cargo_owner"]
