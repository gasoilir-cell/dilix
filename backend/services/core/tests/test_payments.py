"""تست‌های واحدِ M1 — بدونِ نیاز به دیتابیس/NATS:
Outbox، adapterِ sandbox پرداخت، و ماشینِ حالتِ سفارش.
"""
from __future__ import annotations

import json

import pytest

from dilix_shared.adapter import AdapterError, AdapterRegistry


# ---------- Outbox: سریال‌سازیِ ردیف برای انتقال ----------
def test_outbox_serialize_is_valid_json() -> None:
    import uuid
    from datetime import datetime, timezone
    from types import SimpleNamespace

    from app.core.relay import _serialize

    row = SimpleNamespace(
        id=uuid.uuid4(),
        name="payments.EscrowHeld",
        schema_version=1,
        occurred_at=datetime.now(timezone.utc),
        region="IR",
        correlation_id=None,
        payload={"order_id": "o1", "amount_minor": 1000},
    )
    body = json.loads(_serialize(row))
    assert body["name"] == "payments.EscrowHeld"
    assert body["payload"]["amount_minor"] == 1000
    assert body["event_id"] == str(row.id)


# ---------- Adapter Registry ----------
def test_adapter_registry_get_and_unknown() -> None:
    reg: AdapterRegistry[str] = AdapterRegistry()
    reg.register("saman", "adapter-obj")
    assert reg.get("saman") == "adapter-obj"
    with pytest.raises(AdapterError):
        reg.get("unknown")


def test_adapter_registry_rejects_duplicate() -> None:
    reg: AdapterRegistry[str] = AdapterRegistry()
    reg.register("a", "x")
    with pytest.raises(ValueError):
        reg.register("a", "y")


# ---------- Sandbox Payment Adapter: چرخه‌ی escrow ----------
@pytest.mark.asyncio
async def test_sandbox_escrow_capture_flow() -> None:
    from app.modules.payments.adapters.sandbox import SandboxPaymentAdapter
    from app.modules.payments.ports import EscrowRequest

    adapter = SandboxPaymentAdapter()
    res = await adapter.create_escrow(
        EscrowRequest(
            order_ref="o1",
            amount_minor=5000,
            currency="IRR",
            payer_ref="p",
            payee_ref="q",
        )
    )
    assert res.status == "held"
    cap = await adapter.capture(res.external_ref)
    assert cap.status == "captured"
    # capture دوباره روی امانتِ غیرِ held → خطا
    with pytest.raises(AdapterError):
        await adapter.capture(res.external_ref)


@pytest.mark.asyncio
async def test_sandbox_rejects_nonpositive_amount() -> None:
    from app.modules.payments.adapters.sandbox import SandboxPaymentAdapter
    from app.modules.payments.ports import EscrowRequest

    adapter = SandboxPaymentAdapter()
    with pytest.raises(AdapterError):
        await adapter.create_escrow(
            EscrowRequest(
                order_ref="o", amount_minor=0, currency="IRR", payer_ref="p", payee_ref="q"
            )
        )


# ---------- ماشینِ حالتِ سفارش ----------
def test_payment_state_machine_valid_and_invalid() -> None:
    from app.modules.payments.models import (
        STATUS_CAPTURED,
        STATUS_CREATED,
        STATUS_ESCROWED,
        STATUS_REFUNDED,
    )
    from app.modules.payments.state import can_transition, is_terminal

    assert can_transition(STATUS_CREATED, STATUS_ESCROWED)
    assert can_transition(STATUS_ESCROWED, STATUS_CAPTURED)
    assert can_transition(STATUS_ESCROWED, STATUS_REFUNDED)
    # نمی‌توان از created مستقیماً capture کرد
    assert not can_transition(STATUS_CREATED, STATUS_CAPTURED)
    # حالت‌های نهایی هیچ گذاری ندارند
    assert is_terminal(STATUS_CAPTURED)
    assert is_terminal(STATUS_REFUNDED)
    assert not can_transition(STATUS_CAPTURED, STATUS_REFUNDED)
