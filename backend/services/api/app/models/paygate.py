"""
Dilix — مدلِ درگاه‌های پرداختِ pluggable (رجیستری) + قصدِ پرداخت (Intent)
لایهٔ جهانیِ پول: هر بانک/پلتفرمِ مالی می‌تواند درگاهِ خود را در `payment_gateways`
ثبت کند (زرین‌پال، سامان، PayPal، Stripe/Visa، Google Pay، ...). شارژِ کیف‌پول از
مسیرِ `PaymentIntent` انجام و در verify یک‌بار (idempotent) به کیف‌پول واریز می‌شود.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, Float, Integer, String, JSON, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import ForeignKey

from app.core.database import Base


def _now():
    return datetime.now(timezone.utc)


class PaymentGateway(Base):
    __tablename__ = "payment_gateways"

    id        = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code      = Column(String(40), unique=True, nullable=False, index=True)  # zarinpal, saman, stripe, paypal...
    name      = Column(String(120), nullable=False)
    adapter   = Column(String(40), nullable=False, default="mock")           # zarinpal | stripe | mock
    provider_id = Column(UUID(as_uuid=True), nullable=True, index=True)       # ارائه‌دهندهٔ متصل (اختیاری)
    supported_currencies = Column(JSON, nullable=False, default=list)         # ["IRR"]؛ [] = همهٔ ارزها
    countries = Column(JSON, nullable=False, default=list)                    # ["IR"]؛ [] = همهٔ کشورها
    logo_url  = Column(String(300), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    is_sandbox= Column(Boolean, nullable=False, default=True)                 # True → از آداپتورِ Mock استفاده کن
    sort_order= Column(Integer, nullable=False, default=100)
    created_at= Column(DateTime(timezone=True), nullable=False, default=_now)


class PaymentIntent(Base):
    __tablename__ = "payment_intents"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id       = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    gateway_code  = Column(String(40), nullable=False, index=True)
    amount        = Column(BigInteger, nullable=False)   # مبلغِ پرداخت (واحدِ خردِ ارزِ درگاه)
    currency      = Column(String(3), nullable=False)    # ارزِ پرداخت
    credit_currency = Column(String(3), nullable=True)   # ارزِ واریز (کیف‌پول)؛ NULL → همان currency
    credit_amount = Column(BigInteger, nullable=True)    # مبلغِ واریز پس از FX؛ NULL → همان amount
    fx_rate       = Column(Float, nullable=True)         # نرخِ اعمال‌شده (واحدِ credit به‌ازای ۱ واحدِ pay)
    status        = Column(String(12), nullable=False, default="pending")    # pending | paid | failed | canceled
    authority     = Column(String(200), nullable=True, index=True)
    ref_id        = Column(String(200), nullable=True)
    wallet_credited = Column(Boolean, nullable=False, default=False)
    description   = Column(String(200), nullable=True)
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now)
    paid_at       = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (Index("ix_payment_intent_user_status", "user_id", "status"),)
