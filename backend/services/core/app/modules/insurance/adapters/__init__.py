"""رجیستریِ adapterهای بیمه. بیمه‌گرهای واقعی (بیمه البرز) در ادامه ثبت می‌شوند."""
from __future__ import annotations

from dilix_shared.adapter import AdapterRegistry

from app.modules.insurance.adapters.sandbox import SandboxInsuranceAdapter
from app.modules.insurance.ports import InsurancePort

insurance_registry: AdapterRegistry[InsurancePort] = AdapterRegistry()
insurance_registry.register("sandbox", SandboxInsuranceAdapter())

__all__ = ["insurance_registry"]
