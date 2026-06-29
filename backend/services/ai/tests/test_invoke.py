"""تست‌هایِ dilix-ai-service — قرارداد، Supervisor، fallback و کاتالوگ.

این تست‌ها بدونِ هیچ تماسِ خارجی (LLM/Core) اجرا می‌شوند.
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from app.agents import ALL_AGENTS, AGENT_SYSTEM_PROMPTS, MCP_TOOLS, tools_for_agent
from app.main import app
from app.supervisor import resolve_agent, route

client = TestClient(app)


# ─────────────────────── Health & Catalog ──────────────────────────

def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["service"] == "ai"
    assert body["llm_enabled"] is False  # بدونِ کلید در تست


def test_agents_catalog_lists_all_agents() -> None:
    r = client.get("/v1/agents")
    assert r.status_code == 200
    agents = {a["type"] for a in r.json()["agents"]}
    assert agents == set(ALL_AGENTS)


def test_every_agent_has_prompt() -> None:
    for agent in ALL_AGENTS:
        assert AGENT_SYSTEM_PROMPTS.get(agent), f"prompt گم‌شده برای {agent}"


# ─────────────────────── Supervisor routing ──────────────────────────

def test_route_freight() -> None:
    assert route("می‌خواهم یک بار برای راننده ثبت کنم") == "freight"


def test_route_insurance() -> None:
    assert route("استعلام بیمه‌نامه می‌خواهم") == "insurance"


def test_route_default_personal() -> None:
    assert route("سلام حالت چطوره") == "personal"


def test_resolve_respects_explicit_agent() -> None:
    # agentِ صریحِ غیر-personal نباید بازنویسی شود حتی اگر کلیدواژه‌ی دیگری باشد
    assert resolve_agent("insurance", "می‌خواهم بار بفرستم") == "insurance"


def test_resolve_personal_falls_to_supervisor() -> None:
    assert resolve_agent("personal", "دنبالِ راننده برای محموله هستم") == "freight"


# ─────────────────────── MCP tool catalog ──────────────────────────

def test_tools_for_agent_freight() -> None:
    assert "freight.search" in tools_for_agent("freight")


def test_all_agents_can_use_profile() -> None:
    for agent in ALL_AGENTS:
        assert "profile.get" in tools_for_agent(agent)


def test_payment_tool_targets_escrow() -> None:
    assert MCP_TOOLS["payment.create_order"]["path"] == "/v1/payments/escrow"


# ─────────────────────── Invoke contract ──────────────────────────

def test_invoke_returns_contract_shape() -> None:
    r = client.post(
        "/v1/invoke",
        json={
            "agent_type": "personal",
            "conversation_id": "11111111-1111-1111-1111-111111111111",
            "earth_id": "22222222-2222-2222-2222-222222222222",
            "system_prompt": "تو دستیار تست هستی.",
            "history": [],
            "message": "سلام",
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert "reply" in body and isinstance(body["reply"], str) and body["reply"]
    assert body["tool_calls"] == []
    assert body["metadata"]["engine"] == "fallback"
    assert body["metadata"]["agent_type"] == "personal"


def test_invoke_supervisor_reroutes_personal() -> None:
    r = client.post(
        "/v1/invoke",
        json={
            "agent_type": "personal",
            "conversation_id": "c",
            "earth_id": "e",
            "history": [],
            "message": "می‌خواهم بیمه‌نامه خودرو استعلام بگیرم",
        },
    )
    assert r.status_code == 200
    assert r.json()["metadata"]["agent_type"] == "insurance"


def test_invoke_rejects_unknown_agent() -> None:
    r = client.post(
        "/v1/invoke",
        json={
            "agent_type": "wizard",
            "conversation_id": "c",
            "earth_id": "e",
            "history": [],
            "message": "سلام",
        },
    )
    assert r.status_code == 422


def test_invoke_history_passed_through() -> None:
    r = client.post(
        "/v1/invoke",
        json={
            "agent_type": "personal",
            "conversation_id": "c",
            "earth_id": "e",
            "history": [
                {"role": "user", "content": "سفارشِ قبلیِ من چه شد؟"},
                {"role": "assistant", "content": "در حالِ بررسی."},
            ],
            "message": "ممنون",
        },
    )
    assert r.status_code == 200
    assert r.json()["reply"]
