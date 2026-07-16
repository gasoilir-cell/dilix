from __future__ import annotations

import uuid

import pytest


@pytest.mark.asyncio
async def test_ai_chat_persists_user_and_assistant_messages(integration, monkeypatch) -> None:
    import app.modules.ai.service as service

    async def fake_invoke_agent(**kwargs) -> str:  # noqa: ANN003
        assert kwargs["agent_type"] == "personal"
        assert kwargs["user_message"] == "سلام"
        return "پاسخ تستی"

    monkeypatch.setattr(service, "invoke_agent", fake_invoke_agent)

    r = await integration.client.post(
        "/v1/ai/conversations",
        json={"agent_type": "personal", "title": "تست دستیار"},
    )
    assert r.status_code == 201, r.text
    conv_id = r.json()["id"]

    r = await integration.client.post(f"/v1/ai/conversations/{conv_id}/chat", json={"message": "سلام"})
    assert r.status_code == 200, r.text
    reply = r.json()
    assert reply["role"] == "assistant"
    assert reply["content"] == "پاسخ تستی"

    r = await integration.client.get(f"/v1/ai/conversations/{conv_id}/history")
    assert r.status_code == 200, r.text
    history = r.json()
    assert [m["role"] for m in history] == ["user", "assistant"]
    assert [m["content"] for m in history] == ["سلام", "پاسخ تستی"]


@pytest.mark.asyncio
async def test_ai_chat_rejects_other_users_conversation(integration, monkeypatch) -> None:
    import app.modules.ai.service as service

    async def fake_invoke_agent(**_kwargs) -> str:  # noqa: ANN003
        return "نباید فراخوانی شود"

    monkeypatch.setattr(service, "invoke_agent", fake_invoke_agent)

    r = await integration.client.post("/v1/ai/conversations", json={"agent_type": "personal"})
    assert r.status_code == 201, r.text
    conv_id = r.json()["id"]

    integration.as_user(uuid.uuid4())
    r = await integration.client.post(f"/v1/ai/conversations/{conv_id}/chat", json={"message": "سلام"})
    assert r.status_code == 403
