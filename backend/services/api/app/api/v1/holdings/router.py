"""
Dilix — Holdings Router (کیف‌پولِ چندارزی + تبدیلِ درون‌کیفی).

هر کاربر می‌تواند علاوه بر ارزِ پایه، جیب‌های ارزیِ دیگر (USD/EUR/…) نگه دارد و
با نرخِ لایهٔ FX بینِ جیب‌های خودش تبدیل کند. کیف‌پولِ اصلی (`wallets`) کماکان
کانِّالِ ارزِ پایه است؛ جیب‌ها فقط ارزهای افزوده را نگه می‌دارند.

GET  /api/v1/holdings           فهرستِ جیب‌های ارزی + ارزشِ کل (پایه/USD)
POST /api/v1/holdings/exchange  تبدیلِ ارز بینِ جیب‌های خودِ کاربر
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.models.holdings import WalletHolding, HoldingTransaction
from app.services.fx import get_rate_map, convert_minor, unit_rate, minor_scale
from app.services.crypto_wallet import is_crypto, network_of, deposit_address

router = APIRouter(prefix="/holdings", tags=["holdings"])

MIN_EXCHANGE = 1              # واحدِ خردِ ارزِ مبدأ
MAX_EXCHANGE = 1_000_000_000  # سقفِ واحدِ خرد
MAX_AMOUNT = 100_000_000_000  # سقفِ واحدِ خرد برای انتقال/برداشت


def _now():
    return datetime.now(timezone.utc)


async def _get_or_create_wallet(db: AsyncSession, user: User) -> Wallet:
    res = await db.execute(select(Wallet).where(Wallet.user_id == user.id))
    w = res.scalar_one_or_none()
    if w is None:
        w = Wallet(user_id=user.id, currency=(getattr(user, "currency", None) or "IRR"))
        db.add(w)
        await db.flush()
    return w


async def _get_holding(db: AsyncSession, user_id, cur: str) -> Optional[WalletHolding]:
    res = await db.execute(
        select(WalletHolding).where(
            WalletHolding.user_id == user_id, WalletHolding.currency == cur
        )
    )
    return res.scalar_one_or_none()


async def _get_or_create_holding(db: AsyncSession, user_id, cur: str) -> WalletHolding:
    h = await _get_holding(db, user_id, cur)
    if h is None:
        h = WalletHolding(user_id=user_id, currency=cur, balance=0)
        db.add(h)
        await db.flush()
    return h


def _usd_value(balance_minor: int, cur: str, rates) -> Optional[float]:
    if cur not in rates:
        return None
    return round((balance_minor / minor_scale(cur)) * rates[cur], 2)


async def _snapshot(db: AsyncSession, user: User, wallet: Wallet) -> dict:
    base = (wallet.currency or "IRR").upper()
    rates = await get_rate_map(db)

    def base_value(bal: int, cur: str):
        try:
            return convert_minor(bal, cur, base, rates)
        except ValueError:
            return None

    res = await db.execute(select(WalletHolding).where(WalletHolding.user_id == user.id))
    holdings = res.scalars().all()

    pockets = [{
        "currency": base, "balance": wallet.balance_available, "scale": minor_scale(base),
        "is_primary": True, "usd_value": _usd_value(wallet.balance_available, base, rates),
        "base_value": wallet.balance_available,
    }]
    for h in holdings:
        cur = (h.currency or "").upper()
        pockets.append({
            "currency": cur, "balance": h.balance, "scale": minor_scale(cur),
            "is_primary": False, "usd_value": _usd_value(h.balance, cur, rates),
            "base_value": base_value(h.balance, cur),
        })

    total_base = sum(p["base_value"] for p in pockets if p["base_value"] is not None)
    total_usd = round(sum(p["usd_value"] for p in pockets if p["usd_value"] is not None), 2)
    return {"base_currency": base, "pockets": pockets,
            "total_base": total_base, "total_usd": total_usd}


class ExchangeIn(BaseModel):
    from_currency: str = Field(min_length=3, max_length=3)
    to_currency: str = Field(min_length=3, max_length=3)
    amount: int = Field(gt=0, description="مبلغ در واحدِ خردِ ارزِ مبدأ")


@router.get("")
async def list_holdings(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, user)
    await db.commit()
    return await _snapshot(db, user, wallet)


@router.post("/exchange")
async def exchange(
    body: ExchangeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    frm = body.from_currency.upper()
    to = body.to_currency.upper()
    if frm == to:
        raise HTTPException(status_code=400, detail="ارزِ مبدأ و مقصد یکسان است")
    if body.amount < MIN_EXCHANGE or body.amount > MAX_EXCHANGE:
        raise HTTPException(status_code=400, detail="مبلغِ نامعتبر")

    wallet = await _get_or_create_wallet(db, user)
    if wallet.is_frozen:
        raise HTTPException(status_code=400, detail="کیف‌پول مسدود است")
    base = (wallet.currency or "IRR").upper()

    rates = await get_rate_map(db)
    try:
        converted = convert_minor(body.amount, frm, to, rates)
        rate = unit_rate(frm, to, rates)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    if converted <= 0:
        raise HTTPException(status_code=400, detail="مبلغِ نتیجهٔ تبدیل بسیار کوچک است")

    meta = {"kind": "fx_exchange", "from": frm, "to": to,
            "from_amount": body.amount, "to_amount": converted, "rate": rate}

    # ── برداشت از جیبِ مبدأ ──
    if frm == base:
        if wallet.balance_available < body.amount:
            raise HTTPException(status_code=400, detail="موجودیِ کافی نیست")
        before = wallet.balance_available
        wallet.balance_available = before - body.amount
        db.add(WalletTransaction(
            wallet_id=wallet.id, type="exchange", status="completed",
            amount=body.amount, balance_before=before, balance_after=wallet.balance_available,
            description=f"تبدیلِ ارز {frm}→{to}", metadata_={**meta, "direction": "out"},
        ))
    else:
        h_from = await _get_holding(db, user.id, frm)
        if h_from is None or h_from.balance < body.amount:
            raise HTTPException(status_code=400, detail="موجودیِ ارزِ مبدأ کافی نیست")
        h_from.balance -= body.amount
        db.add(HoldingTransaction(
            user_id=user.id, currency=frm, type="exchange_out", status="completed",
            amount=body.amount, balance_after=h_from.balance, counterparty=to,
            description=f"تبدیلِ ارز {frm}→{to}",
        ))

    # ── واریز به جیبِ مقصد ──
    if to == base:
        before = wallet.balance_available
        wallet.balance_available = before + converted
        db.add(WalletTransaction(
            wallet_id=wallet.id, type="exchange", status="completed",
            amount=converted, balance_before=before, balance_after=wallet.balance_available,
            description=f"تبدیلِ ارز {frm}→{to}", metadata_={**meta, "direction": "in"},
        ))
    else:
        h_to = await _get_or_create_holding(db, user.id, to)
        h_to.balance += converted
        db.add(HoldingTransaction(
            user_id=user.id, currency=to, type="exchange_in", status="completed",
            amount=converted, balance_after=h_to.balance, counterparty=frm,
            description=f"تبدیلِ ارز {frm}→{to}",
        ))

    await db.commit()
    await db.refresh(wallet)
    snap = await _snapshot(db, user, wallet)
    return {
        "from_currency": frm, "to_currency": to,
        "from_amount": body.amount, "to_amount": converted, "rate": rate,
        **snap,
    }


# ─── دریافت/ارسال/برداشتِ ارزِ دیجیتال و جیب‌های ارزی ─────────────────────────
class HoldingTransferIn(BaseModel):
    to_earth_id: str = Field(min_length=3, max_length=40)
    currency: str = Field(min_length=3, max_length=8)
    amount: int = Field(gt=0, description="مبلغ در واحدِ خردِ ارز")
    description: Optional[str] = None


class HoldingWithdrawIn(BaseModel):
    currency: str = Field(min_length=3, max_length=8)
    amount: int = Field(gt=0, description="مبلغ در واحدِ خردِ ارز")
    address: str = Field(min_length=6, max_length=120)
    description: Optional[str] = None


def _tx_out(t: HoldingTransaction) -> dict:
    return {
        "id": str(t.id), "currency": (t.currency or "").upper(), "type": t.type,
        "status": t.status, "amount": t.amount, "balance_after": t.balance_after,
        "counterparty": t.counterparty, "description": t.description,
        "created_at": t.created_at.isoformat() if t.created_at else None,
    }


@router.get("/transactions")
async def holding_transactions(
    currency: Optional[str] = None,
    page: int = 1,
    limit: int = 20,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """تاریخچهٔ تراکنش‌های جیب‌های ارزی/کریپتو (اختیاری: فیلترِ یک ارز)."""
    stmt = select(HoldingTransaction).where(HoldingTransaction.user_id == user.id)
    if currency:
        stmt = stmt.where(HoldingTransaction.currency == currency.upper())
    stmt = (stmt.order_by(HoldingTransaction.created_at.desc())
            .offset((max(page, 1) - 1) * limit).limit(limit))
    res = await db.execute(stmt)
    return [_tx_out(t) for t in res.scalars().all()]


@router.get("/{currency}/receive")
async def receive_info(
    currency: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """اطلاعاتِ دریافت: آدرسِ واریزِ کریپتو + شبکه + Earth ID برای انتقالِ درون‌شبکه."""
    cur = currency.upper()
    info = {
        "currency": cur,
        "earth_id": user.earth_id,           # برای دریافتِ درون‌شبکه‌ای از کاربرانِ نقطه
        "is_crypto": is_crypto(cur),
    }
    if is_crypto(cur):
        info.update({
            "address": deposit_address(user.id, cur),
            "network": network_of(cur),
            "note": "فقط همین ارز را روی همین شبکه به این آدرس بفرستید.",
        })
    return info


@router.post("/transfer")
async def holding_transfer(
    body: HoldingTransferIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """انتقالِ درون‌شبکه‌ایِ ارز/کریپتو به کاربرِ دیگرِ نقطه با Earth ID (آنی، بدونِ کارمزد)."""
    cur = body.currency.upper()
    if body.amount > MAX_AMOUNT:
        raise HTTPException(status_code=400, detail="مبلغِ نامعتبر")

    wallet = await _get_or_create_wallet(db, user)
    if wallet.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    base = (wallet.currency or "IRR").upper()

    rec_res = await db.execute(select(User).where(User.earth_id == body.to_earth_id))
    recipient = rec_res.scalar_one_or_none()
    if recipient is None:
        raise HTTPException(status_code=404, detail="کاربرِ مقصد یافت نشد")
    if recipient.id == user.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید به خودتان انتقال دهید")
    rec_wallet = await _get_or_create_wallet(db, recipient)

    if cur == base:
        # انتقالِ ارزِ پایه از مسیرِ کیف‌پولِ اصلی
        if wallet.balance_available < body.amount:
            raise HTTPException(status_code=400, detail="موجودیِ کافی نیست")
        bs = wallet.balance_available
        wallet.balance_available = bs - body.amount
        db.add(WalletTransaction(
            wallet_id=wallet.id, type="transfer_out", status="completed",
            amount=body.amount, balance_before=bs, balance_after=wallet.balance_available,
            description=body.description or f"انتقال به {body.to_earth_id}",
        ))
        br = rec_wallet.balance_available
        rec_wallet.balance_available = br + body.amount
        db.add(WalletTransaction(
            wallet_id=rec_wallet.id, type="transfer_in", status="completed",
            amount=body.amount, balance_before=br, balance_after=rec_wallet.balance_available,
            description=f"دریافت از {user.earth_id}",
        ))
        new_balance = wallet.balance_available
    else:
        h_from = await _get_holding(db, user.id, cur)
        if h_from is None or h_from.balance < body.amount:
            raise HTTPException(status_code=400, detail="موجودیِ ارزِ انتخابی کافی نیست")
        h_from.balance -= body.amount
        db.add(HoldingTransaction(
            user_id=user.id, currency=cur, type="transfer_out", status="completed",
            amount=body.amount, balance_after=h_from.balance, counterparty=body.to_earth_id,
            description=body.description or f"انتقال به {body.to_earth_id}",
        ))
        h_to = await _get_or_create_holding(db, recipient.id, cur)
        h_to.balance += body.amount
        db.add(HoldingTransaction(
            user_id=recipient.id, currency=cur, type="transfer_in", status="completed",
            amount=body.amount, balance_after=h_to.balance, counterparty=user.earth_id,
            description=f"دریافت از {user.earth_id}",
        ))
        new_balance = h_from.balance

    await db.commit()
    return {"success": True, "currency": cur, "amount": body.amount,
            "to": body.to_earth_id, "balance": new_balance}


@router.post("/withdraw")
async def holding_withdraw(
    body: HoldingWithdrawIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """برداشتِ کریپتو به آدرسِ بیرونی. مبلغ بلافاصله قفل/کسر و در صفِ تسویه (pending) ثبت می‌شود؛
    پردازشِ آن‌چین توسطِ سرویسِ تسویه انجام می‌شود."""
    cur = body.currency.upper()
    if not is_crypto(cur):
        raise HTTPException(status_code=400, detail="برداشتِ بیرونی فقط برای ارزِ دیجیتال است")
    if body.amount > MAX_AMOUNT:
        raise HTTPException(status_code=400, detail="مبلغِ نامعتبر")

    wallet = await _get_or_create_wallet(db, user)
    if wallet.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")

    h = await _get_holding(db, user.id, cur)
    if h is None or h.balance < body.amount:
        raise HTTPException(status_code=400, detail="موجودیِ کافی نیست")
    h.balance -= body.amount
    tx = HoldingTransaction(
        user_id=user.id, currency=cur, type="withdrawal", status="pending",
        amount=body.amount, balance_after=h.balance, counterparty=body.address,
        description=body.description or f"برداشتِ {cur} به {network_of(cur)}",
    )
    db.add(tx)
    await db.commit()
    await db.refresh(tx)
    return {"success": True, "status": "pending", "currency": cur,
            "amount": body.amount, "address": body.address, "balance": h.balance,
            "transaction": _tx_out(tx)}
