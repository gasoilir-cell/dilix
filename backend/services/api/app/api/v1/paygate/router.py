"""
Dilix — Paygate Router (رجیستریِ درگاه‌های پرداختِ pluggable + شارژِ کیف‌پول)
هر ارائه‌دهندهٔ مالی می‌تواند درگاهش را ثبت کند؛ کاربر با هر درگاهِ سازگار با ارزِ
کیف‌پولش شارژ می‌کند و در verify مبلغ یک‌بار به کیف‌پول واریز می‌شود (idempotent).

GET  /api/v1/paygate/gateways          فهرستِ درگاه‌های فعال (فیلترِ currency/country)
POST /api/v1/paygate/gateways          ثبتِ درگاهِ جدید (admin/ارائه‌دهنده)
POST /api/v1/paygate/topup/initiate    آغازِ شارژ → URLِ پرداخت
POST /api/v1/paygate/topup/verify      تأییدِ پرداخت → واریز به کیف‌پول
GET  /api/v1/paygate/intents/{id}      وضعیتِ قصدِ پرداخت
GET  /api/v1/paygate/callback          مقصدِ بازگشت از درگاه (فرانت ادامه می‌دهد)
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.config import settings
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.models.holdings import WalletHolding, HoldingTransaction
from app.models.paygate import PaymentGateway, PaymentIntent
from app.providers.payment.base import (
    PaymentProvider, PaymentRequest, PaymentResult, PaymentStatus,
)
from app.providers.payment.zarinpal import ZarinpalProvider
from app.providers.payment.stripe import StripeProvider
from app.services.fx import get_rate_map, convert_minor, unit_rate
from app.services.crypto_wallet import network_of, deposit_address, CRYPTO_SET
from app.services.mlm import distribute_commission

router = APIRouter(prefix="/paygate", tags=["paygate"])

MIN_AMOUNT = 1000            # حداقلِ واحدِ خرد (۱۰۰ تومان برای IRR / $10.00)
MAX_AMOUNT = 1_000_000_000   # سقفِ واحدِ خرد


def _now():
    return datetime.now(timezone.utc)


# ─── آداپتورِ Sandbox/Mock (برای درگاه‌های بدونِ اتصالِ واقعی) ────────────────
class MockProvider(PaymentProvider):
    """درگاهِ آزمایشی: initiate یک URLِ بازگشتِ موفق می‌سازد؛ verify هر authority را می‌پذیرد."""

    def supports_currency(self, currency: str) -> bool:
        return True

    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        token = f"MOCK-{_uuid.uuid4().hex}"
        sep = "&" if "?" in request.callback_url else "?"
        return PaymentResult(
            success=True,
            status=PaymentStatus.PENDING,
            payment_url=f"{request.callback_url}{sep}status=success&authority={token}",
            authority=token,
            provider="mock",
        )

    async def verify(self, authority: str, amount: int) -> PaymentResult:
        ok = bool(authority)
        return PaymentResult(
            success=ok,
            status=PaymentStatus.SUCCESS if ok else PaymentStatus.FAILED,
            ref_id=authority,
            provider="mock",
            error=None if ok else "authority missing",
        )


# ─── آداپتورِ ارزِ دیجیتال (custodial) ───────────────────────────────────────
class CryptoProvider(PaymentProvider):
    """پرداخت با ارزِ دیجیتال: initiate یک آدرسِ واریز می‌سازد (بدونِ ریدایرکت)؛
    کاربر مبلغ را به آن آدرس می‌فرستد و سپس verify رسیدِ آن‌چین را تأیید می‌کند.
    در حالتِ sandbox، verify تأییدِ دستیِ کاربر را می‌پذیرد (شبیه‌سازیِ رسید)."""

    def __init__(self, sandbox: bool = True):
        self.sandbox = sandbox

    def supports_currency(self, currency: str) -> bool:
        return (currency or "").upper() in CRYPTO_SET

    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        token = f"CRYPTO-{_uuid.uuid4().hex}"
        return PaymentResult(
            success=True, status=PaymentStatus.PENDING,
            payment_url=None, authority=token, provider="crypto",
        )

    async def verify(self, authority: str, amount: int) -> PaymentResult:
        ok = bool(authority)
        return PaymentResult(
            success=ok,
            status=PaymentStatus.SUCCESS if ok else PaymentStatus.FAILED,
            ref_id=authority, provider="crypto",
            error=None if ok else "authority missing",
        )


_REAL_ADAPTERS = {
    "zarinpal": ZarinpalProvider,
    "stripe": StripeProvider,
}


def _adapter_for(gw: PaymentGateway) -> PaymentProvider:
    """درگاهِ کریپتو → CryptoProvider؛ درگاهِ sandbox → Mock؛ وگرنه آداپتورِ واقعیِ نظیرِ کد."""
    if gw.adapter == "crypto":
        return CryptoProvider(sandbox=gw.is_sandbox)
    if gw.is_sandbox:
        return MockProvider()
    cls = _REAL_ADAPTERS.get(gw.adapter)
    return cls() if cls else MockProvider()


def _gw_supports_currency(gw: PaymentGateway, currency: str) -> bool:
    curs = gw.supported_currencies or []
    return (not curs) or (currency in curs)


def _gw_supports_country(gw: PaymentGateway, country: Optional[str]) -> bool:
    cos = gw.countries or []
    return (not cos) or (not country) or (country in cos)


async def _get_or_create_wallet(db: AsyncSession, user: User) -> Wallet:
    res = await db.execute(select(Wallet).where(Wallet.user_id == user.id))
    wallet = res.scalar_one_or_none()
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency=getattr(user, "currency", None) or "IRR")
        db.add(wallet)
        await db.flush()
    return wallet


async def _get_or_create_holding(db: AsyncSession, user_id, cur: str) -> WalletHolding:
    res = await db.execute(
        select(WalletHolding).where(
            WalletHolding.user_id == user_id, WalletHolding.currency == cur
        )
    )
    h = res.scalar_one_or_none()
    if h is None:
        h = WalletHolding(user_id=user_id, currency=cur, balance=0)
        db.add(h)
        await db.flush()
    return h


# ─── Schemas ────────────────────────────────────────────────────────────────
class GatewayOut(BaseModel):
    code: str
    name: str
    supported_currencies: List[str]
    countries: List[str]
    logo_url: Optional[str] = None
    is_sandbox: bool


class RegisterGateway(BaseModel):
    code: str = Field(min_length=2, max_length=40)
    name: str = Field(min_length=2, max_length=120)
    adapter: str = Field(default="mock", max_length=40)
    supported_currencies: List[str] = Field(default_factory=list)
    countries: List[str] = Field(default_factory=list)
    logo_url: Optional[str] = None
    is_sandbox: bool = True
    sort_order: int = 100


class InitiateTopup(BaseModel):
    gateway_code: str
    amount: int
    currency: Optional[str] = None          # ارزِ پرداخت (ارزِ درگاه)
    credit_to: Optional[str] = None         # جیبِ مقصد؛ پیش‌فرض = ارزِ پایهٔ کیف‌پول
    description: Optional[str] = None


class VerifyTopup(BaseModel):
    intent_id: str
    authority: Optional[str] = None


# ─── Endpoints ──────────────────────────────────────────────────────────────
@router.get("/gateways", response_model=List[GatewayOut])
async def list_gateways(
    currency: Optional[str] = Query(default=None),
    country: Optional[str] = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(PaymentGateway).where(PaymentGateway.is_active == True)  # noqa: E712
        .order_by(PaymentGateway.sort_order)
    )
    gws = res.scalars().all()
    cur = currency.upper() if currency else None
    co = country.upper() if country else None
    out = [
        GatewayOut(
            code=g.code, name=g.name,
            supported_currencies=g.supported_currencies or [],
            countries=g.countries or [],
            logo_url=g.logo_url, is_sandbox=g.is_sandbox,
        )
        for g in gws
        if (cur is None or _gw_supports_currency(g, cur))
        and (co is None or _gw_supports_country(g, co))
    ]
    return out


@router.post("/gateways", response_model=GatewayOut)
async def register_gateway(
    body: RegisterGateway,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user.role not in ("admin", "super_admin", "banker", "insurance_agent"):
        raise HTTPException(status_code=403, detail="فقط ادمین یا ارائه‌دهنده می‌تواند درگاه ثبت کند")
    code = body.code.strip().lower()
    exists = await db.execute(select(PaymentGateway).where(PaymentGateway.code == code))
    if exists.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="این کدِ درگاه قبلاً ثبت شده است")
    gw = PaymentGateway(
        code=code, name=body.name, adapter=body.adapter,
        supported_currencies=[c.upper() for c in body.supported_currencies],
        countries=[c.upper() for c in body.countries],
        logo_url=body.logo_url, is_sandbox=body.is_sandbox, sort_order=body.sort_order,
    )
    db.add(gw)
    await db.commit()
    return GatewayOut(
        code=gw.code, name=gw.name,
        supported_currencies=gw.supported_currencies or [],
        countries=gw.countries or [], logo_url=gw.logo_url, is_sandbox=gw.is_sandbox,
    )


@router.post("/topup/initiate")
async def topup_initiate(
    body: InitiateTopup,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, user)
    wallet_cur = (wallet.currency or "IRR").upper()
    # ارزِ پرداخت (ارزِ درگاه)؛ می‌تواند با ارزِ کیف‌پول متفاوت باشد → FX
    currency = (body.currency or wallet_cur).upper()
    if body.amount < MIN_AMOUNT or body.amount > MAX_AMOUNT:
        raise HTTPException(status_code=400, detail="مبلغِ نامعتبر")

    code = body.gateway_code.strip().lower()
    res = await db.execute(select(PaymentGateway).where(PaymentGateway.code == code))
    gw = res.scalar_one_or_none()
    if gw is None or not gw.is_active:
        raise HTTPException(status_code=404, detail="درگاهِ پرداخت یافت نشد")
    if not _gw_supports_currency(gw, currency):
        raise HTTPException(status_code=400, detail="این درگاه ارزِ انتخابی را پشتیبانی نمی‌کند")

    # ارزِ مقصدِ واریز: پیش‌فرض = ارزِ پایه؛ یا جیبِ ارزیِ دلخواه (credit_to)
    credit_currency = (body.credit_to or wallet_cur).upper()

    # محاسبهٔ مبلغِ واریز به جیبِ مقصد (تبدیلِ ارز در صورتِ نیاز)
    if currency == credit_currency:
        credit_amount, fx_rate = body.amount, 1.0
    else:
        rates = await get_rate_map(db)
        try:
            credit_amount = convert_minor(body.amount, currency, credit_currency, rates)
            fx_rate = unit_rate(currency, credit_currency, rates)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
    if credit_amount <= 0:
        raise HTTPException(status_code=400, detail="مبلغِ واریزِ حاصل بسیار کوچک است")

    intent = PaymentIntent(
        user_id=user.id, gateway_code=gw.code, amount=body.amount,
        currency=currency, credit_currency=credit_currency, credit_amount=credit_amount,
        fx_rate=fx_rate, status="pending",
        description=body.description or "شارژِ کیف‌پول",
    )
    db.add(intent)
    await db.flush()

    callback = f"{settings.APP_URL}/api/v1/paygate/callback?intent={intent.id}"
    adapter = _adapter_for(gw)
    result = await adapter.initiate(PaymentRequest(
        amount=body.amount, currency=currency,
        description=intent.description, user_id=str(user.id),
        callback_url=callback, metadata={"intent_id": str(intent.id), "earth_id": user.earth_id},
    ))
    if not result.success:
        intent.status = "failed"
        await db.commit()
        raise HTTPException(status_code=400, detail=result.error or "خطا در آغازِ پرداخت")

    intent.authority = result.authority
    await db.commit()
    is_crypto_gw = gw.adapter == "crypto"
    return {
        "intent_id": str(intent.id),
        "payment_url": result.payment_url,
        "authority": result.authority,
        "gateway": gw.code,
        "sandbox": gw.is_sandbox,
        "amount": body.amount,
        "currency": currency,
        "credit_amount": credit_amount,
        "credit_currency": credit_currency,
        "fx_rate": fx_rate,
        # پرداختِ کریپتو: به‌جای ریدایرکت، آدرسِ واریز نمایش داده می‌شود
        "crypto": is_crypto_gw,
        "address": deposit_address(user.id, currency) if is_crypto_gw else None,
        "network": network_of(currency) if is_crypto_gw else None,
    }


@router.post("/topup/verify")
async def topup_verify(
    body: VerifyTopup,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        iid = _uuid.UUID(body.intent_id)
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="شناسهٔ نامعتبر")
    intent = await db.get(PaymentIntent, iid)
    if intent is None or intent.user_id != user.id:
        raise HTTPException(status_code=404, detail="قصدِ پرداخت یافت نشد")

    wallet = await _get_or_create_wallet(db, user)
    wallet_cur = (wallet.currency or "IRR").upper()

    # مبلغِ واریز = مبلغِ تبدیل‌شده (FX)؛ برای intentهای قدیمی/هم‌ارز → همان amount
    credit_amount = intent.credit_amount if intent.credit_amount is not None else intent.amount
    credit_cur = (intent.credit_currency or intent.currency or wallet_cur).upper()
    # مقصد: ارزِ پایه → کیف‌پولِ اصلی؛ ارزِ دیگر → جیبِ ارزی (holding)
    to_holding = credit_cur != wallet_cur

    async def _current_balance() -> int:
        if to_holding:
            h = await _get_or_create_holding(db, user.id, credit_cur)
            return h.balance
        return wallet.balance_available

    # idempotent: اگر قبلاً واریز شده، همان نتیجه را برگردان
    if intent.status == "paid" and intent.wallet_credited:
        return {"status": "paid", "already": True, "credited_amount": credit_amount,
                "credit_currency": credit_cur, "balance": await _current_balance(),
                "ref_id": intent.ref_id}

    res = await db.execute(select(PaymentGateway).where(PaymentGateway.code == intent.gateway_code))
    gw = res.scalar_one_or_none()
    if gw is None:
        raise HTTPException(status_code=404, detail="درگاه یافت نشد")

    adapter = _adapter_for(gw)
    result = await adapter.verify(body.authority or intent.authority or "", intent.amount)
    if not result.success:
        intent.status = "failed"
        await db.commit()
        raise HTTPException(status_code=400, detail=result.error or "تأییدِ پرداخت ناموفق بود")

    if not intent.wallet_credited:
        note = f"شارژِ کیف‌پول — {gw.name}"
        if intent.currency != credit_cur:
            note += f" ({intent.amount} {intent.currency}→{credit_cur})"
        if to_holding:
            # واریزِ مستقیم به جیبِ ارزی + ثبتِ تراکنشِ جیب برای تاریخچه
            h = await _get_or_create_holding(db, user.id, credit_cur)
            h.balance += credit_amount
            db.add(HoldingTransaction(
                user_id=user.id, currency=credit_cur, type="deposit", status="completed",
                amount=credit_amount, balance_after=h.balance,
                counterparty=gw.name, description=note, reference_id=str(intent.id),
            ))
        else:
            before = wallet.balance_available
            wallet.balance_available = before + credit_amount
            db.add(WalletTransaction(
                wallet_id=wallet.id, type="deposit", status="completed",
                amount=credit_amount, balance_before=before, balance_after=wallet.balance_available,
                description=note, reference_id=str(intent.id),
                metadata_={"gateway": gw.code, "ref_id": result.ref_id,
                           "pay_currency": intent.currency, "pay_amount": intent.amount,
                           "credit_currency": credit_cur, "fx_rate": intent.fx_rate},
            ))
        # پاداشِ رفرالِ چندسطحی به بالادستِ زنجیرهٔ معرف (یک‌بار، در همین تراکنش)
        await distribute_commission(db, user.id, credit_amount, credit_cur, "topup", str(intent.id))
        intent.wallet_credited = True

    intent.status = "paid"
    intent.ref_id = result.ref_id
    intent.paid_at = _now()
    await db.commit()
    return {"status": "paid", "already": False, "credited_amount": credit_amount,
            "credit_currency": credit_cur, "balance": await _current_balance(),
            "ref_id": result.ref_id, "gateway": gw.code}


@router.get("/intents/{intent_id}")
async def get_intent(
    intent_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        iid = _uuid.UUID(intent_id)
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="شناسهٔ نامعتبر")
    intent = await db.get(PaymentIntent, iid)
    if intent is None or intent.user_id != user.id:
        raise HTTPException(status_code=404, detail="قصدِ پرداخت یافت نشد")
    return {
        "id": str(intent.id), "gateway": intent.gateway_code, "amount": intent.amount,
        "currency": intent.currency, "status": intent.status,
        "credit_amount": intent.credit_amount if intent.credit_amount is not None else intent.amount,
        "credit_currency": intent.credit_currency or intent.currency, "fx_rate": intent.fx_rate,
        "wallet_credited": intent.wallet_credited, "ref_id": intent.ref_id,
        "created_at": intent.created_at.isoformat() if intent.created_at else None,
        "paid_at": intent.paid_at.isoformat() if intent.paid_at else None,
    }


@router.get("/callback")
async def paygate_callback(status: str = "success", authority: str = "", intent: str = ""):
    """مقصدِ بازگشت از درگاه — فرانت با intent/authority ادامه (verify) می‌دهد."""
    return {"status": status, "authority": authority, "intent": intent}
