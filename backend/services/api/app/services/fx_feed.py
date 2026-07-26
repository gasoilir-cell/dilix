"""
Dilix — فیدِ زندهٔ نرخِ ارز (FX live feed).

سرورِ ایران‌میزبان به APIهای Cloudflare-fronted (er-api/frankfurter) دسترسی ندارد؛
تنها منبعِ قابل‌دسترس `api.tgju.org` است که نرخِ USD/IRRِ بازار را می‌دهد. این سرویس
نرخِ IRR را — که بیشترین نوسان و تأثیر را روی درآمدِ ریالی/دلاری دارد — از این فید
به‌روز می‌کند؛ سایرِ ارزها روی نرخِ مرجعِ ثابت می‌مانند تا منبعِ جهانیِ قابل‌دسترس اضافه شود.
"""
import asyncio
from datetime import datetime, timezone
from typing import Optional

import httpx
import structlog
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.fx import FxRate

log = structlog.get_logger(__name__)

# قیمتِ دلار برحسبِ ریال (بازار) — تنها اندپوینتِ tgjuِ قابل‌دسترس از ایران
TGJU_USD_IRR_URL = (
    "https://api.tgju.org/v1/market/indicator/summary-table-data/price_dollar_rl"
)
# مرزهای معقول برای ردِ داده‌های خراب (ریال به ازای هر دلار)
_MIN_RIAL_PER_USD = 100_000
_MAX_RIAL_PER_USD = 100_000_000

# ارزهای دیجیتال از فیدِ tgju (قیمتِ پایانی برحسبِ USD). کدها ۳ حرفی تا با
# ستونِ String(3)ِ جدولِ fx_rates بدونِ مهاجرت سازگار بمانند.
CRYPTO_SLUGS = {
    "BTC": "crypto-bitcoin",
    "ETH": "crypto-ethereum",
    "TON": "crypto-toncoin",
    "TRX": "crypto-tron",
}
_TGJU_CRYPTO_URL = (
    "https://api.tgju.org/v1/market/indicator/summary-table-data/{slug}"
)


async def fetch_usd_irr_rial() -> Optional[float]:
    """قیمتِ پایانیِ دلار برحسبِ ریال از tgju؛ None اگر ناموفق/نامعتبر.

    شکلِ پاسخ: {"data": [[open, low, high, close, ...], ...]} — ردیفِ اول تازه‌ترین
    است و ستونِ اندیسِ ۳ «پایانی» (close) را دارد.
    """
    try:
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            r = await client.get(TGJU_USD_IRR_URL)
            r.raise_for_status()
            data = r.json().get("data") or []
        if not data or not data[0] or len(data[0]) < 4:
            return None
        close = str(data[0][3]).replace(",", "").strip()      # ستونِ «پایانی»
        rial = float(close)
        if not (_MIN_RIAL_PER_USD <= rial <= _MAX_RIAL_PER_USD):
            return None
        return rial
    except Exception as e:                                     # noqa: BLE001
        log.warning("fx_feed_fetch_failed", err=str(e))
        return None


async def refresh_irr_from_feed(db) -> dict:
    """نرخِ IRR را در `fx_rates` از فیدِ زنده به‌روز می‌کند (upsert). commit می‌کند."""
    rial = await fetch_usd_irr_rial()
    if rial is None:
        return {"updated": False, "reason": "feed_unavailable"}
    usd_per_unit = 1.0 / rial                                  # USD به ازای ۱ ریال
    res = await db.execute(select(FxRate).where(FxRate.currency == "IRR"))
    row = res.scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if row is None:
        db.add(FxRate(currency="IRR", usd_per_unit=usd_per_unit,
                      source="tgju:usd_rl", updated_at=now))
    else:
        row.usd_per_unit = usd_per_unit
        row.source = "tgju:usd_rl"
        row.updated_at = now
    await db.commit()
    return {
        "updated": True,
        "currency": "IRR",
        "rial_per_usd": rial,
        "usd_per_unit": usd_per_unit,
        "source": "tgju:usd_rl",
        "updated_at": now.isoformat(),
    }


async def _fetch_crypto_usd(client: "httpx.AsyncClient", slug: str):
    """قیمتِ پایانیِ کریپتو برحسبِ USD از tgju؛ None اگر ناموفق/نامعتبر."""
    try:
        r = await client.get(_TGJU_CRYPTO_URL.format(slug=slug))
        r.raise_for_status()
        data = r.json().get("data") or []
        if not data or not data[0] or len(data[0]) < 4:
            return None
        close = str(data[0][3]).replace(",", "").strip()     # ستونِ «پایانی»
        val = float(close)
        return val if val > 0 else None
    except Exception as e:                                     # noqa: BLE001
        log.warning("fx_crypto_fetch_failed", slug=slug, err=str(e))
        return None


async def refresh_crypto_from_feed(db) -> dict:
    """نرخِ ارزهای دیجیتال را در `fx_rates` از فیدِ زندهٔ tgju upsert می‌کند.

    هر ارز مستقل واکشی می‌شود؛ شکستِ یکی بقیه را متوقف نمی‌کند (fail-safe).
    """
    now = datetime.now(timezone.utc)
    updated = []
    try:
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            for code, slug in CRYPTO_SLUGS.items():
                usd = await _fetch_crypto_usd(client, slug)
                if usd is None:
                    continue
                res = await db.execute(select(FxRate).where(FxRate.currency == code))
                row = res.scalar_one_or_none()
                if row is None:
                    db.add(FxRate(currency=code, usd_per_unit=usd,
                                  source="tgju:crypto", updated_at=now))
                else:
                    row.usd_per_unit = usd
                    row.source = "tgju:crypto"
                    row.updated_at = now
                updated.append({"currency": code, "usd_per_unit": usd})
        if updated:
            await db.commit()
    except Exception as e:                                     # noqa: BLE001
        log.warning("fx_crypto_refresh_error", err=str(e))
    return {"updated": bool(updated), "count": len(updated), "items": updated}


async def refresh_once_safe() -> dict:
    """یک نوبت به‌روزرسانی با سشنِ مستقل؛ هرگز استثنا بیرون نمی‌دهد."""
    try:
        async with AsyncSessionLocal() as db:
            result = await refresh_irr_from_feed(db)
            crypto = await refresh_crypto_from_feed(db)
        log.info("fx_feed_refresh", updated=result.get("updated"),
                 rial_per_usd=result.get("rial_per_usd"),
                 crypto=crypto.get("count"))
        result["crypto"] = crypto
        return result
    except Exception as e:                                     # noqa: BLE001
        log.warning("fx_feed_refresh_error", err=str(e))
        return {"updated": False, "reason": "error"}


async def periodic_fx_refresh(interval_seconds: int = 6 * 3600,
                              initial_delay: int = 25) -> None:
    """حلقهٔ به‌روزرسانیِ دوره‌ای؛ در lifespan به‌صورتِ task اجرا می‌شود.

    با `initial_delay` از تأخیرِ بوت جلوگیری می‌کند و هرگز استثنا بیرون نمی‌دهد
    (پس نبودِ اینترنت/فید هیچ‌گاه اپ را متوقف نمی‌کند).
    """
    try:
        await asyncio.sleep(initial_delay)
        while True:
            await refresh_once_safe()
            await asyncio.sleep(interval_seconds)
    except asyncio.CancelledError:
        pass
