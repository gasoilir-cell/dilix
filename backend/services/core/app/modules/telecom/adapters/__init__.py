from dilix_shared.adapter import AdapterRegistry
from app.modules.telecom.adapters.sandbox import SandboxTelecomAdapter
from app.modules.telecom.ports import TelecomPort

telecom_registry: AdapterRegistry[TelecomPort] = AdapterRegistry()
telecom_registry.register("sandbox", SandboxTelecomAdapter())
