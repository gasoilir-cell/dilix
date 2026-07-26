"""
Dilix — سرویسِ تبدیلِ ارز (FX). تبدیل بینِ واحدهای خردِ ذخیره‌شده در کیف‌پول/درگاه.

واحدِ خردِ ذخیره‌سازی برای هر ارز = ۱۰^decimals (IRR با ۰ اعشار → واحدِ ریال، مقیاس ۱؛
بقیه با ۲ اعشار → cent، مقیاس ۱۰۰). نرخ‌ها از جدولِ `fx_rates` (usd_per_unit) خوانده می‌شوند.
"""
from typing import Dict

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fx import FxRate

# ارزهای بدونِ زیرواحد (۰ اعشار) → مقیاسِ واحدِ خرد = ۱
ZERO_DECIMAL = {"IRR", "JPY", "KRW", "VND", "CLP", "ISK"}

# ارزهای دیجیتال (کریپتو) با اعشارِ بیشتر برای دقتِ نگهداری در واحدِ خرد
CRYPTO_DECIMALS = {"BTC": 8, "ETH": 8, "TON": 6, "TRX": 6}


def minor_scale(currency: str) -> int:
    """تعدادِ واحدِ خرد در هر واحدِ ISO (IRR→۱ ریال، USD→۱۰۰ cent، BTC→۱۰^۸ ساتوشی)."""
    c = currency.upper()
    if c in ZERO_DECIMAL:
        return 1
    if c in CRYPTO_DECIMALS:
        return 10 ** CRYPTO_DECIMALS[c]
    return 100


async def get_rate_map(db: AsyncSession) -> Dict[str, float]:
    res = await db.execute(select(FxRate))
    return {r.currency.upper(): r.usd_per_unit for r in res.scalars().all()}


def convert_minor(amount_minor: int, frm: str, to: str, rates: Dict[str, float]) -> int:
    """تبدیلِ مبلغِ واحدِ خردِ ارزِ frm به واحدِ خردِ ارزِ to با عبور از USD."""
    frm, to = frm.upper(), to.upper()
    if frm == to:
        return amount_minor
    if frm not in rates or to not in rates:
        raise ValueError(f"نرخِ ارز برای {frm}→{to} موجود نیست")
    major_from = amount_minor / minor_scale(frm)
    usd = major_from * rates[frm]
    major_to = usd / rates[to]
    return int(round(major_to * minor_scale(to)))


def unit_rate(frm: str, to: str, rates: Dict[str, float]) -> float:
    """چند واحدِ ISO از to به‌ازای ۱ واحدِ ISO از frm (برای نمایش/ثبت)."""
    frm, to = frm.upper(), to.upper()
    if frm == to:
        return 1.0
    if frm not in rates or to not in rates:
        raise ValueError(f"نرخِ ارز برای {frm}→{to} موجود نیست")
    return rates[frm] / rates[to]
