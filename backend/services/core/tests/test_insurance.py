"""تست‌های واحدِ M2 — بیمه: adapterِ sandbox و ماشینِ حالت (بدونِ DB)."""
from __future__ import annotations

import pytest

from dilix_shared.adapter import AdapterError


@pytest.mark.asyncio
async def test_sandbox_quote_issue_claim_flow() -> None:
    from app.modules.insurance.adapters.sandbox import SandboxInsuranceAdapter
    from app.modules.insurance.ports import QuoteRequest

    adapter = SandboxInsuranceAdapter()
    quote = await adapter.quote(
        QuoteRequest(
            product_code="cargo",
            holder_ref="h",
            coverage_minor=1_000_000,
            currency="IRR",
            attributes={},
        )
    )
    # حقِ بیمه = ۲٪ پوشش
    assert quote.premium_minor == 20_000
    issued = await adapter.issue(quote.quote_ref)
    assert issued.status == "issued"
    clm = await adapter.claim(issued.external_ref, 500_000, "تصادف")
    assert clm.status == "registered"


@pytest.mark.asyncio
async def test_sandbox_issue_unknown_quote_fails() -> None:
    from app.modules.insurance.adapters.sandbox import SandboxInsuranceAdapter

    adapter = SandboxInsuranceAdapter()
    with pytest.raises(AdapterError):
        await adapter.issue("nope")


def test_insurance_state_machine() -> None:
    from app.modules.insurance.models import (
        STATUS_CLAIMED,
        STATUS_ISSUED,
        STATUS_QUOTED,
    )
    from app.modules.insurance.state import can_transition, is_terminal

    assert can_transition(STATUS_QUOTED, STATUS_ISSUED)
    assert can_transition(STATUS_ISSUED, STATUS_CLAIMED)
    assert not can_transition(STATUS_QUOTED, STATUS_CLAIMED)
    assert is_terminal(STATUS_CLAIMED)
