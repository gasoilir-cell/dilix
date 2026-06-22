"""موتور تصمیم مجوز (PDP) — RBAC + ABAC سبک (سند ۶).

در Milestone بعد به OPA/Cedar منتقل می‌شود؛ این‌جا یک ارزیاب درون‌فرایندی
برای شروع است. ساختار ورودی/خروجی عمداً با OPA سازگار است.
"""
from __future__ import annotations

from dataclasses import dataclass

# RBAC: نگاشت نقش → مجموعه‌ی permission (نمونه‌ی اولیه)
_COMMON = {
    "identity.read_self",
    "identity.update_self",
    "kyc.submit",
    "messaging.use",
    "social.post",
    "social.comment",
    "social.react",
    "social.follow",
    "notification.read",
    "earth.update_location",
    "earth.view_pois",
    "ai.chat",
    "gamification.read",
    "membership.read",
    "membership.upgrade",
    "referral.register",
    "payments.create_escrow",
    "payments.capture",
    "payments.refund",
    "insurance.quote",
    "insurance.issue",
    "insurance.claim",
    "telecom.top_up",
    "telecom.esim",
    "investment.buy",
    "investment.sell",
    "investment.view",
}

ROLE_PERMISSIONS: dict[str, set[str]] = {
    "individual": _COMMON,
    "driver": _COMMON | {
        "freight.place_bid",
        "freight.confirm_pickup",
        "freight.confirm_delivery",
        "carrier.track",
    },
    "cargo_owner": _COMMON | {
        "freight.post",
        "freight.accept_bid",
        "freight.release_escrow",
        "freight.confirm_delivery",
        "carrier.create_waybill",
        "carrier.track",
        "earth.create_poi",
    },
    "logistics": _COMMON | {
        "freight.post",
        "freight.place_bid",
        "freight.accept_bid",
        "freight.release_escrow",
        "freight.confirm_pickup",
        "freight.confirm_delivery",
        "carrier.create_waybill",
        "carrier.track",
        "earth.create_poi",
    },
    "insurer": {
        "identity.read_self",
        "identity.update_self",
        "kyc.submit",
    },
    "insurance_agent": _COMMON,
    "financial": _COMMON | {"investment.buy", "investment.sell"},
    "telecom": {"identity.read_self", "identity.update_self"},
    "freelancer": _COMMON | {"social.post"},
    "healthcare": {"identity.read_self"},
    "education": {"identity.read_self"},
    "government": {"identity.read_self"},
    "moderator": _COMMON | {"social.moderate", "kyc.review"},
    "regional_admin": _COMMON | {"kyc.review", "provider.manage"},
    "country_admin": _COMMON | {"kyc.review", "provider.manage", "earth.manage_pois"},
    "global_admin": {"*"},
}


@dataclass(slots=True)
class AccessRequest:
    subject_role: str
    subject_kyc_level: int
    subject_earth_id: str
    action: str
    resource_owner_id: str | None = None
    resource_status: str | None = None
    required_kyc_level: int = 0


def is_allowed(req: AccessRequest) -> bool:
    """ترکیب RBAC (آیا نقش اجازه‌ی action را دارد) و ABAC (شرایط زمینه‌ای)."""
    perms = ROLE_PERMISSIONS.get(req.subject_role, set())
    if "*" not in perms and req.action not in perms:
        return False

    # ABAC: حداقل سطح KYC
    if req.subject_kyc_level < req.required_kyc_level:
        return False

    # ABAC: مالکیت منبع برای اقدامات حساس (جلوگیری از IDOR)
    if req.resource_owner_id is not None and req.resource_owner_id != req.subject_earth_id:
        if "*" not in perms:
            return False

    return True
