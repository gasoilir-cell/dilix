"""Earth ID — شناسه‌ی جهانیِ یکتای هر موجودیت در GESA (Shared Kernel / Value Object).

طبق ADR-04، فقط شناسه و متادیتای حداقلی هویتی بین‌ریجنی است؛
داده‌ی شخصی در ریجن کشور کاربر می‌ماند.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from enum import Enum


class EntityType(str, Enum):
    """انواع موجودیت دارای Earth ID (مطابق User Types سند اصلی)."""

    INDIVIDUAL = "individual"
    BUSINESS = "business"
    CARGO_OWNER = "cargo_owner"
    DRIVER = "driver"
    LOGISTICS = "logistics"
    INSURER = "insurer"
    INSURANCE_AGENT = "insurance_agent"
    FINANCIAL = "financial"
    TELECOM = "telecom"
    FREELANCER = "freelancer"
    HEALTHCARE = "healthcare"
    EDUCATION = "education"
    GOVERNMENT = "government"
    MODERATOR = "moderator"
    REGIONAL_ADMIN = "regional_admin"
    COUNTRY_ADMIN = "country_admin"
    GLOBAL_ADMIN = "global_admin"


# نقش‌هایی که نیاز به مسیر KYB (Know Your Business) دارند، نه KYC فردی.
BUSINESS_LIKE_TYPES = frozenset(
    {
        EntityType.BUSINESS,
        EntityType.LOGISTICS,
        EntityType.INSURER,
        EntityType.FINANCIAL,
        EntityType.TELECOM,
        EntityType.HEALTHCARE,
        EntityType.EDUCATION,
        EntityType.GOVERNMENT,
    }
)


@dataclass(frozen=True, slots=True)
class EarthId:
    """Value Object تغییرناپذیر برای شناسه‌ی جهانی."""

    value: uuid.UUID

    @classmethod
    def new(cls) -> "EarthId":
        return cls(uuid.uuid4())

    @classmethod
    def parse(cls, raw: str | uuid.UUID) -> "EarthId":
        return cls(raw if isinstance(raw, uuid.UUID) else uuid.UUID(str(raw)))

    def __str__(self) -> str:  # pragma: no cover - trivial
        return str(self.value)
