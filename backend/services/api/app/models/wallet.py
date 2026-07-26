"""
Dilix — مدل کیف پول و تراکنش
"""
import uuid
from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime,
    Enum, ForeignKey, Index, String, Text, JSON, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.core.database import Base


class Wallet(Base):
    __tablename__ = "wallets"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id     = Column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True, nullable=False)
    currency    = Column(String(3), default="IRR", nullable=False)

    # موجودی‌ها (به ریال × 100 = ریال دقیق)
    balance_available = Column(BigInteger, default=0, nullable=False)
    balance_escrow    = Column(BigInteger, default=0, nullable=False)
    balance_bonus     = Column(BigInteger, default=0, nullable=False)

    is_frozen   = Column(Boolean, default=False)
    frozen_reason = Column(Text, nullable=True)

    created_at  = Column(DateTime(timezone=True), server_default=func.now())
    updated_at  = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user        = relationship("User", backref="wallet")

    @property
    def total_balance(self) -> int:
        return self.balance_available + self.balance_bonus


class WalletTransaction(Base):
    __tablename__ = "wallet_transactions"

    id              = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wallet_id       = Column(UUID(as_uuid=True), ForeignKey("wallets.id"), nullable=False, index=True)
    reference_id    = Column(String(100), nullable=True, index=True)  # شماره تراکنش بانک

    type            = Column(
        Enum(
            "deposit", "withdrawal", "escrow_lock", "escrow_release",
            "transfer_in", "transfer_out", "refund", "bonus", "fee", "exchange",
            name="wallet_tx_type_enum",
        ),
        nullable=False,
    )
    status          = Column(
        Enum("pending", "completed", "failed", "reversed", name="wallet_tx_status_enum"),
        default="pending",
    )
    amount          = Column(BigInteger, nullable=False)  # همیشه مثبت
    balance_before  = Column(BigInteger, nullable=False)
    balance_after   = Column(BigInteger, nullable=False)
    description     = Column(Text, nullable=True)
    metadata_       = Column("metadata", JSON, default=dict)
    created_at      = Column(DateTime(timezone=True), server_default=func.now())

    wallet          = relationship("Wallet", backref="transactions")

    __table_args__ = (
        Index("ix_wallet_tx_created", "wallet_id", "created_at"),
        Index("ix_wallet_tx_type_status", "type", "status"),
    )
