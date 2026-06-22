from dilix_shared.adapter import AdapterRegistry
from app.modules.investment.adapters.sandbox import SandboxInvestmentAdapter
from app.modules.investment.ports import InvestmentPort

investment_registry: AdapterRegistry[InvestmentPort] = AdapterRegistry()
investment_registry.register("sandbox_fund", SandboxInvestmentAdapter())
