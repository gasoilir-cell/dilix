"""تست‌های واحدِ M2 — حمل‌ونقل: adapterِ sandbox و ماشینِ حالت (بدونِ DB)."""
from __future__ import annotations

import pytest

from dilix_shared.adapter import AdapterError


@pytest.mark.asyncio
async def test_sandbox_waybill_and_track_flow() -> None:
    from app.modules.carrier.adapters.sandbox import SandboxCarrierAdapter
    from app.modules.carrier.ports import WaybillRequest

    adapter = SandboxCarrierAdapter()
    wb = await adapter.create_waybill(
        WaybillRequest(
            shipment_ref="s1",
            shipper_ref="u",
            origin="تهران",
            destination="مشهد",
            weight_grams=5000,
        )
    )
    assert wb.status == "created"
    info = await adapter.track(wb.waybill_no)
    assert info.status == "in_transit"
    assert info.last_location == "hub-1"


@pytest.mark.asyncio
async def test_sandbox_track_unknown_fails() -> None:
    from app.modules.carrier.adapters.sandbox import SandboxCarrierAdapter

    adapter = SandboxCarrierAdapter()
    with pytest.raises(AdapterError):
        await adapter.track("nope")


def test_carrier_state_machine_and_mapping() -> None:
    from app.modules.carrier.models import (
        STATUS_CREATED,
        STATUS_DELIVERED,
        STATUS_DISPATCHED,
        STATUS_IN_TRANSIT,
    )
    from app.modules.carrier.state import CARRIER_STATUS_MAP, can_transition, is_terminal

    assert can_transition(STATUS_CREATED, STATUS_DISPATCHED)
    assert can_transition(STATUS_DISPATCHED, STATUS_IN_TRANSIT)
    assert can_transition(STATUS_IN_TRANSIT, STATUS_DELIVERED)
    assert not can_transition(STATUS_CREATED, STATUS_DELIVERED)
    assert is_terminal(STATUS_DELIVERED)
    assert CARRIER_STATUS_MAP["in_transit"] == STATUS_IN_TRANSIT
