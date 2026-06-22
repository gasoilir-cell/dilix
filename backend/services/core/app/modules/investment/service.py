"""سرویس سرمایه‌گذاری — خرید/فروشِ واحدِ صندوق (ADR-09: فقط صندوقِ مجاز)."""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.adapter import AdapterError
from dilix_shared.errors import NotFoundError, ProviderError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.investment.adapters import investment_registry
from app.modules.investment.models import InvestmentPosition
from app.modules.investment.ports import UnitBuyRequest, UnitSellRequest
from app.modules.investment.schemas import BuyRequest, SellRequest


async def buy(db: AsyncSession, *, earth_id: uuid.UUID, data: BuyRequest) -> InvestmentPosition:
    adapter = investment_registry.get(data.provider_code)
    try:
        result = await adapter.buy_units(
            UnitBuyRequest(
                investor_ref=str(earth_id),
                fund_code=data.fund_code,
                amount_minor=data.amount_minor,
                currency=data.currency.upper(),
            )
        )
    except AdapterError as exc:
        raise ProviderError(exc.detail) from exc

    pos = InvestmentPosition(
        earth_id=earth_id,
        fund_code=data.fund_code,
        provider_code=data.provider_code,
        units=result.units or 0.0,
        trade_ref=result.trade_ref,
        status="active",
    )
    db.add(pos)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            "investment.UnitsBought",
            {"position_id": str(pos.id), "fund": data.fund_code, "units": pos.units},
        ),
    )
    return pos


async def sell(
    db: AsyncSession, *, earth_id: uuid.UUID, data: SellRequest
) -> InvestmentPosition:
    pos = await db.get(InvestmentPosition, data.position_id)
    if pos is None or pos.earth_id != earth_id:
        raise NotFoundError("موقعیتِ سرمایه‌گذاری یافت نشد.")
    if data.units > pos.units:
        from dilix_shared.errors import ConflictError
        raise ConflictError("تعدادِ واحدِ درخواستی بیش از موجودی است.")

    adapter = investment_registry.get(pos.provider_code)
    try:
        result = await adapter.sell_units(
            UnitSellRequest(investor_ref=str(earth_id), position_ref=str(pos.id), units=data.units)
        )
    except AdapterError as exc:
        raise ProviderError(exc.detail) from exc

    pos.units -= data.units
    if pos.units <= 0:
        pos.status = "closed"
    pos.trade_ref = result.trade_ref
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            "investment.UnitsSold",
            {"position_id": str(pos.id), "units_sold": data.units},
        ),
    )
    return pos


async def get_nav(provider_code: str, fund_code: str) -> int:
    adapter = investment_registry.get(provider_code)
    return await adapter.get_nav(fund_code)


async def my_positions(db: AsyncSession, earth_id: uuid.UUID) -> list[InvestmentPosition]:
    result = await db.execute(
        select(InvestmentPosition)
        .where(InvestmentPosition.earth_id == earth_id, InvestmentPosition.status == "active")
        .order_by(InvestmentPosition.created_at.desc())
    )
    return list(result.scalars().all())
