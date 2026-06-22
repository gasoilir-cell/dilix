"""تست‌های واحدِ M2 — توابعِ خالصِ adapterِ سامان (نگاشت payload و امضای HMAC)."""
from __future__ import annotations

from app.modules.payments.adapters.saman import build_escrow_payload, sign_body
from app.modules.payments.ports import EscrowRequest


def test_build_escrow_payload_maps_fields() -> None:
    body = build_escrow_payload(
        EscrowRequest(
            order_ref="o1",
            amount_minor=12345,
            currency="IRR",
            payer_ref="p",
            payee_ref="q",
        )
    )
    assert body == {
        "order_id": "o1",
        "amount": 12345,
        "currency": "IRR",
        "payer": "p",
        "payee": "q",
    }


def test_sign_body_is_deterministic_and_key_sensitive() -> None:
    body = {"b": 2, "a": 1}
    sig1 = sign_body("secret", body)
    sig2 = sign_body("secret", {"a": 1, "b": 2})  # ترتیب نباید مهم باشد
    assert sig1 == sig2
    assert sign_body("other", body) != sig1
    assert len(sig1) == 64  # SHA-256 hex
