"""ستون فقرات Provider Adapter Framework (ADR-02).

هر vertical یک **Port** تعریف می‌کند (قراردادِ دامنه)؛ هر ارائه‌دهنده یک
**Adapter** پشتِ یک ACL پیاده می‌کند. این ماژول دو چیزِ مشترک می‌دهد:
- `AdapterError`: خطای یکنواخت برای شکستِ سمتِ ارائه‌دهنده.
- `AdapterRegistry`: نگاشتِ کدِ ارائه‌دهنده → نمونه‌ی Adapter.
"""
from __future__ import annotations

from typing import Generic, TypeVar

T = TypeVar("T")


class AdapterError(Exception):
    """شکست در فراخوانیِ ارائه‌دهنده. `code` برای نگاشت به خطای دامنه است."""

    def __init__(self, code: str, detail: str, *, retryable: bool = False) -> None:
        self.code = code
        self.detail = detail
        self.retryable = retryable
        super().__init__(f"[{code}] {detail}")


class AdapterRegistry(Generic[T]):
    """ثبت و یافتنِ adapter بر اساس کدِ یکتای ارائه‌دهنده (مثل 'saman')."""

    def __init__(self) -> None:
        self._adapters: dict[str, T] = {}

    def register(self, code: str, adapter: T) -> None:
        if code in self._adapters:
            raise ValueError(f"adapter قبلاً ثبت شده: {code}")
        self._adapters[code] = adapter

    def get(self, code: str) -> T:
        try:
            return self._adapters[code]
        except KeyError as exc:
            raise AdapterError("provider_not_found", f"adapter ناشناخته: {code}") from exc

    def codes(self) -> list[str]:
        return sorted(self._adapters)
