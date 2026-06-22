"""Adapter sandbox سرمایه‌گذاری — NAV ثابت برای تست."""
from __future__ import annotations
import uuid
from dilix_shared.adapter import AdapterError
from app.modules.investment.ports import (
    InvestmentPort, TradeResult, UnitBuyRequest, UnitSellRequest,
)

_FIXED_NAV = 1_000_000  # ۱,۰۰۰,۰۰۰ ریال per unit


class SandboxInvestmentAdapter(InvestmentPort):
    async def buy_units(self, req: UnitBuyRequest) -> TradeResult:
        if req.amount_minor < _FIXED_NAV:
            raise AdapterError("min_amount", "حداقل مبلغ یک واحد است.")
        units = req.amount_minor / _FIXED_NAV
        return TradeResult(trade_ref=f"tr_{uuid.uuid4().hex[:12]}", status="executed", units=units, nav_minor=_FIXED_NAV)

    async def sell_units(self, req: UnitSellRequest) -> TradeResult:
        if req.units <= 0:
            raise AdapterError("invalid_units", "تعدادِ واحد باید مثبت باشد.")
        return TradeResult(trade_ref=f"tr_{uuid.uuid4().hex[:12]}", status="executed", units=req.units, nav_minor=_FIXED_NAV)

    async def get_nav(self, fund_code: str) -> int:
        return _FIXED_NAV
