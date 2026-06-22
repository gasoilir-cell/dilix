"""Port سرمایه‌گذاری — فقط از طریقِ صندوقِ دارای مجوز (ADR-09).

Dilix کارگزار یا صندوق نیست. فقط درخواستِ خرید/فروش واحد را به صندوقِ
مجوزداری که adapter آن ثبت شده می‌فرستد. هیچ سرمایه‌گذاری مستقیم یا
بدونِ صندوق انجام نمی‌شود.
"""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class UnitBuyRequest:
    investor_ref: str
    fund_code: str
    amount_minor: int   # مبلغِ خرید (نه تعدادِ واحد)
    currency: str


@dataclass(frozen=True, slots=True)
class UnitSellRequest:
    investor_ref: str
    position_ref: str
    units: float


@dataclass(frozen=True, slots=True)
class TradeResult:
    trade_ref: str
    status: str    # pending | executed | failed
    units: float | None = None
    nav_minor: int | None = None   # ارزشِ خالصِ هر واحد


class InvestmentPort(ABC):
    @abstractmethod
    async def buy_units(self, req: UnitBuyRequest) -> TradeResult: ...

    @abstractmethod
    async def sell_units(self, req: UnitSellRequest) -> TradeResult: ...

    @abstractmethod
    async def get_nav(self, fund_code: str) -> int: ...  # ارزشِ خالصِ هر واحد (ریال)
