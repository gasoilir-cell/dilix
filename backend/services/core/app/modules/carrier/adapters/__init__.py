"""رجیستریِ adapterهای حمل‌ونقل. متصدیانِ واقعی در ادامه ثبت می‌شوند."""
from __future__ import annotations

from dilix_shared.adapter import AdapterRegistry

from app.modules.carrier.adapters.sandbox import SandboxCarrierAdapter
from app.modules.carrier.ports import CarrierPort

carrier_registry: AdapterRegistry[CarrierPort] = AdapterRegistry()
carrier_registry.register("sandbox", SandboxCarrierAdapter())

__all__ = ["carrier_registry"]
