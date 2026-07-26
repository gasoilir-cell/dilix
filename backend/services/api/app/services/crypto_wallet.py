"""
Dilix — لایهٔ ارزِ دیجیتال (کریپتو) برای کیف‌پولِ چندارزی.

مدلِ نگه‌داری «custodial» است: موجودیِ کریپتو مثلِ سایرِ جیب‌ها در `wallet_holdings`
نگه‌داری می‌شود (واحدِ خرد = ۱۰^decimals). این ماژول ابزارهای مشترک را فراهم می‌کند:
- تشخیصِ ارزِ کریپتو و نامِ شبکه
- تولیدِ آدرسِ واریزِ قطعی (deterministic) و یکتا برای هر کاربر/ارز

توجه: تولید/تأییدِ تراکنشِ آن‌چین (broadcast) به گرهٔ بلاک‌چین/سرویسِ بیرونی نیاز دارد
که در این استقرار موجود نیست؛ آدرس‌ها custodial و برداشتِ بیرونی «در صفِ پردازش»
ثبت می‌شود تا بعداً توسطِ سرویسِ تسویه پردازش شود.
"""
import hashlib

from app.core.config import settings

# ارزهای دیجیتالِ پشتیبانی‌شده (هم‌راستا با CRYPTO_DECIMALS در services/fx و currency.ts فرانت)
CRYPTO_SET = {"BTC", "ETH", "TON", "TRX"}

# نامِ شبکهٔ هر ارز (برای نمایش به کاربر هنگامِ واریز/برداشت)
CRYPTO_NETWORK = {
    "BTC": "Bitcoin (BTC)",
    "ETH": "Ethereum (ERC-20)",
    "TON": "TON",
    "TRX": "Tron (TRC-20)",
}

# پیشوند و طولِ آدرسِ نمایشی برای هر شبکه (شبیه‌سازیِ قالبِ آدرسِ واقعی)
_ADDR_PREFIX = {"BTC": "bc1q", "ETH": "0x", "TON": "UQ", "TRX": "T"}
_ADDR_LEN = {"BTC": 38, "ETH": 40, "TON": 46, "TRX": 33}


def is_crypto(currency: str | None) -> bool:
    return (currency or "").upper() in CRYPTO_SET


def network_of(currency: str | None) -> str:
    c = (currency or "").upper()
    return CRYPTO_NETWORK.get(c, c)


def deposit_address(user_id, currency: str) -> str:
    """آدرسِ واریزِ custodial، قطعی و یکتا به‌ازای (کاربر، ارز).

    از هشِ SHA-256 روی رازِ سرور + شناسهٔ کاربر + ارز مشتق می‌شود؛ پس برای یک
    کاربر همیشه ثابت است و بینِ کاربران متفاوت.
    """
    c = (currency or "").upper()
    secret = getattr(settings, "JWT_SECRET", "dilix")
    digest = hashlib.sha256(f"{secret}:{user_id}:{c}:v1".encode()).hexdigest()
    prefix = _ADDR_PREFIX.get(c, "0x")
    length = _ADDR_LEN.get(c, 40)
    return prefix + digest[:length]
