"""Wallet API endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction

router = APIRouter(prefix="/wallet", tags=["wallet"])


class WalletResponse(BaseModel):
    id: str
    currency: str
    balance_available: int
    balance_escrow: int
    balance_bonus: int
    is_frozen: bool


class TransactionResponse(BaseModel):
    id: str
    type: str
    status: str
    amount: int
    balance_before: int
    balance_after: int
    description: str | None
    created_at: str


class TransferRequest(BaseModel):
    to_earth_id: str
    amount: int = Field(..., gt=0, description="مبلغ به ریال")
    description: str = ""


async def _get_or_create_wallet(db: AsyncSession, user: User) -> Wallet:
    """کیف پول کاربر را برمی‌گرداند و اگر وجود نداشته باشد می‌سازد.

    برخی حساب‌ها (مثلاً ثبت‌نام با OTP/OAuth یا حساب‌های قدیمی) ممکن است بدون
    کیف پول ساخته شده باشند؛ این‌جا به‌صورت lazy با موجودی صفر ایجاد می‌شود.
    """
    result = await db.execute(select(Wallet).where(Wallet.user_id == user.id))
    wallet = result.scalar_one_or_none()
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency="IRR")
        db.add(wallet)
        await db.commit()
        await db.refresh(wallet)
    return wallet


@router.get("", response_model=WalletResponse, include_in_schema=False)
@router.get("/", response_model=WalletResponse)
async def get_wallet(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, current_user)
    return WalletResponse(
        id=str(wallet.id),
        currency=wallet.currency,
        balance_available=wallet.balance_available,
        balance_escrow=wallet.balance_escrow,
        balance_bonus=wallet.balance_bonus,
        is_frozen=wallet.is_frozen,
    )


@router.get("/transactions", response_model=list[TransactionResponse])
async def get_transactions(
    page: int = 1,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, current_user)

    offset = (page - 1) * limit
    tx_result = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.wallet_id == wallet.id)
        .order_by(WalletTransaction.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    txs = tx_result.scalars().all()
    return [
        TransactionResponse(
            id=str(tx.id),
            type=tx.type,
            status=tx.status,
            amount=tx.amount,
            balance_before=tx.balance_before,
            balance_after=tx.balance_after,
            description=tx.description,
            created_at=tx.created_at.isoformat(),
        )
        for tx in txs
    ]


@router.post("/transfer", response_model=dict)
async def transfer(
    body: TransferRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """انتقال موجودی به کاربر دیگر با Earth ID."""
    result = await db.execute(select(Wallet).where(Wallet.user_id == current_user.id))
    sender_wallet = result.scalar_one_or_none()
    if not sender_wallet:
        raise HTTPException(status_code=404, detail="کیف پول یافت نشد")
    if sender_wallet.is_frozen:
        raise HTTPException(status_code=403, detail="کیف پول مسدود است")
    if sender_wallet.balance_available < body.amount:
        raise HTTPException(status_code=400, detail="موجودی کافی نیست")

    rec_result = await db.execute(select(User).where(User.earth_id == body.to_earth_id))
    recipient = rec_result.scalar_one_or_none()
    if not recipient:
        raise HTTPException(status_code=404, detail="کاربر مقصد یافت نشد")
    if recipient.id == current_user.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید به خودتان انتقال دهید")

    rw_result = await db.execute(select(Wallet).where(Wallet.user_id == recipient.id))
    recipient_wallet = rw_result.scalar_one_or_none()
    if not recipient_wallet:
        raise HTTPException(status_code=404, detail="کیف پول مقصد یافت نشد")

    before_sender = sender_wallet.balance_available
    sender_wallet.balance_available -= body.amount
    db.add(WalletTransaction(
        wallet_id=sender_wallet.id,
        type="transfer_out",
        status="completed",
        amount=body.amount,
        balance_before=before_sender,
        balance_after=sender_wallet.balance_available,
        description=body.description or f"انتقال به {body.to_earth_id}",
    ))

    before_recipient = recipient_wallet.balance_available
    recipient_wallet.balance_available += body.amount
    db.add(WalletTransaction(
        wallet_id=recipient_wallet.id,
        type="transfer_in",
        status="completed",
        amount=body.amount,
        balance_before=before_recipient,
        balance_after=recipient_wallet.balance_available,
        description=f"دریافت از {current_user.earth_id}",
    ))

    await db.commit()
    return {"success": True, "amount": body.amount, "to": body.to_earth_id}
