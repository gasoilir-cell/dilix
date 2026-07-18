from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_webrtc_signal_relay_adds_sender(monkeypatch) -> None:
    from app.modules.realtime.router import _relay_signal
    from app.modules.realtime.schemas import WsEventType
    import app.modules.realtime.router as router

    sent: list[tuple[str, dict]] = []

    async def fake_send_to(earth_id: str, message: dict) -> None:
        sent.append((earth_id, message))

    monkeypatch.setattr(router.manager, "send_to", fake_send_to)

    await _relay_signal(
        WsEventType.CALL_OFFER,
        "user-a",
        {"to": "user-b", "call_id": "c1", "sdp": {"type": "offer"}},
    )

    assert sent == [
        (
            "user-b",
            {
                "type": WsEventType.CALL_OFFER,
                "payload": {"to": "user-b", "call_id": "c1", "sdp": {"type": "offer"}, "from": "user-a"},
                "ts": sent[0][1]["ts"],
            },
        )
    ]


@pytest.mark.asyncio
async def test_webrtc_signal_without_target_is_ignored(monkeypatch) -> None:
    from app.modules.realtime.router import _relay_signal
    from app.modules.realtime.schemas import WsEventType
    import app.modules.realtime.router as router

    called = False

    async def fake_send_to(_earth_id: str, _message: dict) -> None:
        nonlocal called
        called = True

    monkeypatch.setattr(router.manager, "send_to", fake_send_to)

    await _relay_signal(WsEventType.CALL_END, "user-a", {"call_id": "c1"})

    assert called is False


@pytest.mark.asyncio
async def test_ws_rejects_invalid_token(monkeypatch) -> None:
    """اتصالِ WS با توکنِ نامعتبر باید با کدِ 4001 بسته شود و connect صدا نشود."""
    import app.modules.realtime.router as router

    monkeypatch.setattr(router, "decode_token", lambda _t: None)

    connected = False

    async def fake_connect(_ws, _earth_id: str) -> None:
        nonlocal connected
        connected = True

    monkeypatch.setattr(router.manager, "connect", fake_connect)

    closed: dict = {}

    class _FakeWS:
        async def close(self, code: int = 1000, reason: str = "") -> None:
            closed["code"] = code
            closed["reason"] = reason

    await router.websocket_endpoint(_FakeWS(), token="bogus")

    assert closed.get("code") == 4001
    assert connected is False


@pytest.mark.asyncio
async def test_ws_rejects_non_access_token(monkeypatch) -> None:
    """توکنی که نوعِ آن access نیست (مثلاً refresh) باید رد شود."""
    import app.modules.realtime.router as router

    monkeypatch.setattr(router, "decode_token", lambda _t: {"sub": "u1", "type": "refresh"})

    connected = False

    async def fake_connect(_ws, _earth_id: str) -> None:
        nonlocal connected
        connected = True

    monkeypatch.setattr(router.manager, "connect", fake_connect)

    closed: dict = {}

    class _FakeWS:
        async def close(self, code: int = 1000, reason: str = "") -> None:
            closed["code"] = code

    await router.websocket_endpoint(_FakeWS(), token="refresh-token")

    assert closed.get("code") == 4001
    assert connected is False
