"""رجیستریِ adapterهای پرداخت. ارائه‌دهنده‌های واقعی این‌جا ثبت می‌شوند.

- `sandbox`: همیشه ثبت است (برای dev/تست).
- `saman`: فقط اگر در تنظیمات پیکربندی شده باشد (ADR-07، درگاهِ پرداخت‌یاریِ شاپرک).
"""
from __future__ import annotations

from dilix_shared.adapter import AdapterRegistry

from app.core.config import get_settings
from app.modules.payments.adapters.sandbox import SandboxPaymentAdapter
from app.modules.payments.ports import PaymentPort

payment_registry: AdapterRegistry[PaymentPort] = AdapterRegistry()
payment_registry.register("sandbox", SandboxPaymentAdapter())

_settings = get_settings()
if _settings.saman_enabled:
    from app.modules.payments.adapters.saman import SamanPaymentAdapter

    payment_registry.register(
        "saman",
        SamanPaymentAdapter(
            base_url=_settings.saman_base_url,
            terminal_id=_settings.saman_terminal_id,
            secret=_settings.saman_secret,
        ),
    )

__all__ = ["payment_registry"]
