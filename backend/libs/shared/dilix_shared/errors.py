"""خطاهای دامنه‌ی مشترک. لایه‌ی API این‌ها را به RFC 7807 نگاشت می‌کند (سند ۵)."""
from __future__ import annotations


class DilixError(Exception):
    """ریشه‌ی همه‌ی خطاهای دامنه."""

    status_code: int = 400
    error_type: str = "dilix_error"

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class NotFoundError(DilixError):
    status_code = 404
    error_type = "not_found"


class ConflictError(DilixError):
    status_code = 409
    error_type = "conflict"


class ForbiddenError(DilixError):
    status_code = 403
    error_type = "forbidden"


class InsufficientKycError(ForbiddenError):
    error_type = "insufficient_kyc"


class ProviderError(DilixError):
    """شکست در سمتِ ارائه‌دهنده‌ی بیرونی (Adapter). به‌صورتِ 502 نگاشت می‌شود."""

    status_code = 502
    error_type = "provider_error"
