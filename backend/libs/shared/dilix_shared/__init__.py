"""Dilix Shared Kernel — مدل‌ها و قراردادهای مشترک بین Bounded Contextها.

این پکیج فقط شامل مفاهیم پایدار و مشترک است (Earth ID، رویدادها، خطاها).
هیچ منطق دامنه‌ای اختصاصی اینجا قرار نمی‌گیرد.
"""

from .adapter import AdapterError, AdapterRegistry
from .earth_id import EarthId, EntityType
from .events import DomainEvent, EventEnvelope
from .errors import (
    ConflictError,
    ForbiddenError,
    DilixError,
    NotFoundError,
    ProviderError,
)

__all__ = [
    "EarthId",
    "EntityType",
    "DomainEvent",
    "EventEnvelope",
    "DilixError",
    "NotFoundError",
    "ConflictError",
    "ForbiddenError",
    "ProviderError",
    "AdapterError",
    "AdapterRegistry",
]
