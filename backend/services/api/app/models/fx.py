"""
Dilix — نرخِ ارز (FX). لایهٔ جهانیِ پول: امکانِ شارژ/تبدیل بینِ ارزها.
هر ردیف ارزشِ ۱ واحدِ ISO از آن ارز را برحسبِ USD نگه می‌دارد (`usd_per_unit`).
تبدیل از A به B: major_A → USD → major_B (سرویسِ `app/services/fx.py`).
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Float, String
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class FxRate(Base):
    __tablename__ = "fx_rates"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    currency     = Column(String(3), unique=True, nullable=False, index=True)
    usd_per_unit = Column(Float, nullable=False)      # ارزشِ ۱ واحدِ ISO برحسبِ USD
    source       = Column(String(40), nullable=False, default="reference")
    updated_at   = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
