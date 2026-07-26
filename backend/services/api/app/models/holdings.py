"""
Dilix — کیف‌پولِ چندارزی: جیب‌های ارزیِ افزوده (holdings) کنارِ کیف‌پولِ اصلی.

هر کاربر علاوه بر ارزِ پایهٔ کیف‌پولِ اصلی (`wallets.currency`) می‌تواند موجودیِ
ارزهای دیگر (USD/EUR/…) را در جیب‌های جداگانه نگه دارد. تبدیل بینِ جیب‌ها از
لایهٔ FX ([[concepts/globalization]]) انجام می‌شود. کیف‌پولِ اصلی و جریان‌های
موجود (escrow حمل، Red Packet، انتقال) دست‌نخورده می‌مانند.
"""
import uuid

from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, String, Text,
    UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class WalletHolding(Base):
    __tablename__ = "wallet_holdings"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    currency   = Column(String(3), nullable=False)          # ارزِ ISO (غیر از ارزِ پایه)
    balance    = Column(BigInteger, default=0, nullable=False)  # واحدِ خرد

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "currency", name="uq_holding_user_currency"),
        Index("ix_holding_user", "user_id"),
    )


class HoldingTransaction(Base):
    """دفترِ ممیزیِ جیب‌های ارزی/کریپتو (دریافت، ارسال، برداشتِ بیرونی، تبدیل).

    جدا از `wallet_transactions` (که مخصوصِ کیف‌پولِ ارزِ پایه است) نگه‌داری می‌شود
    تا موجودی و مبلغِ ارزهای غیرپایه (به‌ویژه کریپتو با اعشارِ بالا) با معناشناسیِ
    درست ثبت شوند.
    """
    __tablename__ = "holding_transactions"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    currency     = Column(String(8), nullable=False)
    # deposit | withdrawal | transfer_in | transfer_out | exchange_in | exchange_out
    type         = Column(String(20), nullable=False)
    status       = Column(String(12), nullable=False, default="completed")  # completed | pending | failed
    amount       = Column(BigInteger, nullable=False)          # واحدِ خرد، همیشه مثبت
    balance_after = Column(BigInteger, nullable=False)         # موجودیِ جیب پس از تراکنش
    counterparty = Column(String(120), nullable=True)          # Earth ID یا آدرسِ بیرونی
    description  = Column(Text, nullable=True)
    reference_id = Column(String(100), nullable=True, index=True)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index("ix_holding_tx_user_created", "user_id", "created_at"),
    )
