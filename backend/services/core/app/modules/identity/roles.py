"""کاتالوگِ نقش‌ها — متادیتای انسان‌خوان برای هر نقشِ خودسرویس.

منبعِ حقیقتِ «چه نقش‌هایی قابلِ سوییچ‌اند» در ``dilix_shared.earth_id.SELF_SERVICE_ROLES``
است؛ این‌جا فقط برچسب/توضیحِ نمایشی افزوده می‌شود تا فرانت بتواند سوییچرِ نقش را بسازد.
"""
from __future__ import annotations

from dilix_shared.earth_id import SELF_SERVICE_ROLES, EntityType

# نگاشتِ نقش → (برچسبِ فارسی، توضیحِ کوتاه). فقط نقش‌های خودسرویس این‌جا هستند.
ROLE_METADATA: dict[EntityType, tuple[str, str]] = {
    EntityType.INDIVIDUAL: (
        "کاربرِ شخصی",
        "استفاده‌ی روزمره: پیام‌رسان، شبکه‌ی اجتماعی، نقشه و خدمات.",
    ),
    EntityType.DRIVER: (
        "راننده",
        "پیدا کردنِ بار، ثبتِ پیشنهاد و مدیریتِ سفرها و درآمد.",
    ),
    EntityType.CARGO_OWNER: (
        "صاحبِ بار",
        "ثبتِ بار، پذیرشِ پیشنهادِ راننده و پیگیریِ محموله.",
    ),
    EntityType.FREELANCER: (
        "فریلنسر",
        "ارائه‌ی خدمات، نمایشِ نمونه‌کار و جذبِ مشتری.",
    ),
}


def role_catalog() -> list[dict]:
    """کاتالوگِ نقش‌های خودسرویس به‌همراهِ برچسب/توضیح (برای فرانت)."""
    catalog: list[dict] = []
    for role in EntityType:
        if role not in SELF_SERVICE_ROLES:
            continue
        label, description = ROLE_METADATA.get(role, (role.value, ""))
        catalog.append(
            {
                "entity_type": role,
                "label": label,
                "description": description,
                "self_service": True,
            }
        )
    return catalog
