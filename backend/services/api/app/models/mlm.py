"""
Dilix — MLM Commission model (لِجِرِ کمیسیونِ بازاریابیِ چندسطحی).

هر ردیف = یک پرداختِ کمیسیون به یک بالادست (earner) از فعالیتِ یک زیرمجموعه
(source_user) در یک سطحِ مشخص. زنجیرهٔ معرف از `User.referred_by` خوانده می‌شود.
"""
import uuid

from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, Integer, String, func,
)
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class MlmCommission(Base):
    __tablename__ = "mlm_commissions"

    id             = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    earner_id      = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                            nullable=False, index=True)               # بالادستی که درآمد گرفت
    source_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"),
                            nullable=True, index=True)                # زیرمجموعه‌ای که فعالیتش کمیسیون ساخت
    level          = Column(Integer, nullable=False)                  # سطحِ فاصله (۱=مستقیم)
    rate_bps       = Column(Integer, nullable=False)                  # نرخ به basis-point (۸۰۰=۸٪)
    amount         = Column(BigInteger, nullable=False)               # مبلغِ کمیسیون، واحدِ خرد
    currency       = Column(String(3), nullable=False)
    source_type    = Column(String(30), nullable=False, default="topup")
    reference_id   = Column(String(64), nullable=True)               # مثلاً intent_id
    created_at     = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index("ix_mlm_earner_created", "earner_id", "created_at"),
    )
