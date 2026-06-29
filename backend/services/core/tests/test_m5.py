"""تست‌های واحد M5 — Discovery، Growth، Provider Marketplace، WebRTC signaling."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest


# ── Discovery — منطقِ privacy و سن ───────────────────────────────────────────────

def test_discovery_age_from_birth() -> None:
    from app.modules.discovery.service import _age_from_birth
    born = datetime(2000, 1, 1, tzinfo=timezone.utc)
    age = _age_from_birth(born)
    assert age is not None and 24 <= age <= 27


def test_discovery_age_none() -> None:
    from app.modules.discovery.service import _age_from_birth
    assert _age_from_birth(None) is None


def test_discovery_age_to_range() -> None:
    from app.modules.discovery.service import _age_to_range
    assert _age_to_range(27) == "20-29"
    assert _age_to_range(34) == "30-39"
    assert _age_to_range(None) is None


def test_discovery_age_in_range() -> None:
    from app.modules.discovery.service import _age_in_range
    assert _age_in_range(27, "25-34")
    assert not _age_in_range(40, "25-34")
    assert not _age_in_range(None, "25-34")
    assert not _age_in_range(27, "garbage")


def test_discovery_audience_public() -> None:
    from app.modules.discovery.service import _audience_ok
    target = uuid.uuid4()
    assert _audience_ok("public", 0, target, set())


def test_discovery_audience_verified() -> None:
    from app.modules.discovery.service import _audience_ok
    target = uuid.uuid4()
    assert not _audience_ok("verified", 0, target, set())
    assert _audience_ok("verified", 1, target, set())


def test_discovery_audience_connections() -> None:
    from app.modules.discovery.service import _audience_ok
    target = uuid.uuid4()
    assert not _audience_ok("connections", 5, target, set())
    assert _audience_ok("connections", 0, target, {target})


def test_discovery_nearby_person_schema() -> None:
    from app.modules.discovery.schemas import NearbyPerson
    p = NearbyPerson(
        earth_id=uuid.uuid4(),
        entity_type="person",
        display_name="آرش",
        lat=35.7,
        lon=51.4,
        geo_precision="city",
    )
    # فیلدهای gated به‌صورتِ پیش‌فرض None هستند (افشا نشده)
    assert p.gender is None
    assert p.geo_precision == "city"


def test_discovery_bbox_parse() -> None:
    from app.modules.discovery.router import _parse_bbox
    min_lat, max_lat, min_lon, max_lon = _parse_bbox("35.0,51.0,36.0,52.0")
    assert min_lat == 35.0 and max_lat == 36.0
    assert min_lon == 51.0 and max_lon == 52.0


def test_discovery_bbox_empty() -> None:
    from app.modules.discovery.router import _parse_bbox
    assert _parse_bbox(None) == (None, None, None, None)


def test_discovery_bbox_invalid_raises() -> None:
    from app.modules.discovery.router import _BadBbox, _parse_bbox
    with pytest.raises(_BadBbox):
        _parse_bbox("bad")


# ── Growth ───────────────────────────────────────────────────────────────────────

def test_growth_invite_code_deterministic() -> None:
    from app.modules.growth.service import _invite_code
    eid = uuid.uuid4()
    assert _invite_code(eid) == _invite_code(eid)
    assert len(_invite_code(eid)) == 10


def test_growth_revenue_share_bps_table() -> None:
    from app.modules.growth.service import _PLAN_REVENUE_SHARE_BPS
    from app.modules.membership.models import PLAN_FREE, PLAN_PREMIUM
    assert _PLAN_REVENUE_SHARE_BPS[PLAN_FREE] == 0
    assert _PLAN_REVENUE_SHARE_BPS[PLAN_PREMIUM] > 0


def test_growth_reward_wallet_schema() -> None:
    from app.modules.growth.schemas import RewardBalance, RewardWalletOut
    wallet = RewardWalletOut(
        balances=[RewardBalance(currency="IRR", amount_minor=1_000_000, reward_count=2)],
        pending_count=1,
    )
    assert wallet.balances[0].amount_minor == 1_000_000


# ── Provider Marketplace — sandbox/webhook/credential ───────────────────────────

def test_provider_hash_key_stable() -> None:
    from app.modules.provider.service import _hash_key
    assert _hash_key("abc") == _hash_key("abc")
    assert len(_hash_key("abc")) == 64  # sha256 hex


def test_provider_credential_schema() -> None:
    from app.modules.provider.schemas import CredentialCreate, CredentialOut
    req = CredentialCreate(env="sandbox")
    assert req.env == "sandbox"
    out = CredentialOut(
        id=uuid.uuid4(), env="sandbox", key_prefix="dlx_sand_", status="active",
        api_key="dlx_sand_secret",
    )
    assert out.api_key.startswith("dlx_")


def test_provider_webhook_schema() -> None:
    from app.modules.provider.schemas import WebhookCreate
    wh = WebhookCreate(url="https://provider.example/hook", event_types=["freight.delivered"])
    assert "freight.delivered" in wh.event_types


def test_provider_sandbox_result_schema() -> None:
    from app.modules.provider.schemas import SandboxTestResult
    r = SandboxTestResult(api_id=uuid.uuid4(), reachable=True, http_status=200,
                          latency_ms=42, detail="ok")
    assert r.reachable and r.http_status == 200


# ── WebRTC signaling ─────────────────────────────────────────────────────────────

def test_webrtc_event_types() -> None:
    from app.modules.realtime.schemas import WsEventType
    assert WsEventType.CALL_OFFER == "call.offer"
    assert WsEventType.CALL_ANSWER == "call.answer"
    assert WsEventType.ICE_CANDIDATE == "ice.candidate"
    assert WsEventType.CALL_END == "call.end"


def test_webrtc_signal_set() -> None:
    from app.modules.realtime.router import _WEBRTC_SIGNALS
    from app.modules.realtime.schemas import WsEventType
    assert WsEventType.CALL_OFFER in _WEBRTC_SIGNALS
    assert WsEventType.PING not in _WEBRTC_SIGNALS


@pytest.mark.asyncio
async def test_webrtc_relay_forwards_to_target() -> None:
    """relay باید پیام را به earth_id مقصد بفرستد و from را اضافه کند."""
    from app.modules.realtime import router as rt
    from app.modules.realtime.connection_manager import manager
    from app.modules.realtime.schemas import WsEventType

    sent: dict = {}

    async def fake_send_to(target, message):
        sent["target"] = target
        sent["message"] = message

    original = manager.send_to
    manager.send_to = fake_send_to  # type: ignore[assignment]
    try:
        await rt._relay_signal(
            WsEventType.CALL_OFFER, "caller-1", {"to": "callee-2", "sdp": "v=0"}
        )
    finally:
        manager.send_to = original  # type: ignore[assignment]

    assert sent["target"] == "callee-2"
    assert sent["message"]["payload"]["from"] == "caller-1"
    assert sent["message"]["type"] == WsEventType.CALL_OFFER


@pytest.mark.asyncio
async def test_webrtc_relay_without_target_noop() -> None:
    from app.modules.realtime import router as rt
    from app.modules.realtime.connection_manager import manager
    from app.modules.realtime.schemas import WsEventType

    called = False

    async def fake_send_to(target, message):
        nonlocal called
        called = True

    original = manager.send_to
    manager.send_to = fake_send_to  # type: ignore[assignment]
    try:
        await rt._relay_signal(WsEventType.ICE_CANDIDATE, "caller-1", {"candidate": "x"})
    finally:
        manager.send_to = original  # type: ignore[assignment]
    assert not called


# ── AI — Supervisor routing + MCP tools + new agents ────────────────────────────

def test_ai_route_to_freight() -> None:
    from app.modules.ai.langgraph_client import AGENT_FREIGHT, route_to_agent
    assert route_to_agent("می‌خواهم یک بار از تهران به مشهد بفرستم") == AGENT_FREIGHT


def test_ai_route_to_matchmaking() -> None:
    from app.modules.ai.langgraph_client import AGENT_MATCHMAKING, route_to_agent
    assert route_to_agent("دنبالِ دوستِ هم‌علاقه در اطراف هستم") == AGENT_MATCHMAKING


def test_ai_route_default_personal() -> None:
    from app.modules.ai.langgraph_client import AGENT_PERSONAL, route_to_agent
    assert route_to_agent("سلام حالت چطوره") == AGENT_PERSONAL


def test_ai_all_agents_have_prompts() -> None:
    from app.modules.ai.langgraph_client import ALL_AGENTS, AGENT_SYSTEM_PROMPTS
    for agent in ALL_AGENTS:
        assert agent in AGENT_SYSTEM_PROMPTS
        assert len(AGENT_SYSTEM_PROMPTS[agent]) > 10


def test_ai_mcp_tools_for_agent() -> None:
    from app.modules.ai.langgraph_client import AGENT_MATCHMAKING, tools_for_agent
    tools = tools_for_agent(AGENT_MATCHMAKING)
    assert "discovery.find_people" in tools
    assert "profile.get" in tools  # ابزارِ مشترکِ همه


def test_ai_mcp_tool_paths_exist_in_app() -> None:
    """هر مسیرِ MCP باید به یک endpointِ واقعیِ اپ نگاشت شود (ضدِ drift)."""
    from app.main import app
    from app.modules.ai.langgraph_client import MCP_TOOLS

    paths = app.openapi()["paths"]
    for name, spec in MCP_TOOLS.items():
        path, method = spec["path"], spec["method"].lower()
        assert path in paths, f"MCP tool '{name}' مسیرِ نامعتبر دارد: {path}"
        assert method in paths[path], f"MCP tool '{name}' متدِ نامعتبر دارد: {method} {path}"


@pytest.mark.asyncio
async def test_ai_new_agent_stub() -> None:
    from app.modules.ai.langgraph_client import AGENT_BUSINESS, invoke_agent
    reply = await invoke_agent(
        agent_type=AGENT_BUSINESS,
        conversation_id=str(uuid.uuid4()),
        earth_id=str(uuid.uuid4()),
        history=[],
        user_message="دنبالِ شریکِ تجاری هستم",
    )
    assert "BUSINESS" in reply
