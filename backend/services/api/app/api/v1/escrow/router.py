"""
Dilix — پرداختِ امانی مستقیم بینِ دو کاربر (escrow)

    POST /api/v1/payments/escrow             ساختِ سفارشِ امانی (وجه بلوکه می‌شود)
    GET  /api/v1/payments/escrow             سفارش‌های امانیِ من
    POST /api/v1/payments/{id}/capture       تسویه به سودِ گیرنده (held → captured)
    POST /api/v1/payments/{id}/refund        بازگشت به پرداخت‌کننده (held → refunded)

جدا از `/api/v1/payment` که درگاهِ شارژِ کیف است؛ اینجا پول از پیش در کیف است و
فقط بینِ دو کاربر امانی نگه داشته می‌شود.

دو تصمیمی که ساختار را تعیین کرد:

۱) **ردیفِ سفارش پیش از هر تغییرِ وضعیت قفل می‌شود.** بدونِ قفل، دو `capture`
   هم‌زمان هر دو شرطِ `status == held` را رد می‌کردند و وجهِ بلوکه دو بار آزاد
   می‌شد — یعنی از هیچ، پول ساخته می‌شد.

۲) **`capture` حقِ گیرنده یا پرداخت‌کننده است، ولی `refund` فقط حقِ گیرنده.**
   اگر پرداخت‌کننده می‌توانست هر وقت خواست وجه را برگرداند، «امانی» هیچ
   تضمینی برای گیرنده نداشت و با یک انتقالِ ساده فرقی نمی‌کرد.
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, String, or_, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.services.wallet_ops import lock_escrow, refund_escrow, release_escrow

router = APIRouter(prefix="/payments", tags=["Escrow"])

STATUS_HELD = "held"
STATUS_CAPTURED = "captured"
STATUS_REFUNDED = "refunded"


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل ───────────────────────────────────────────────────────────────────────
class PaymentOrder(Base):
    __tablename__ = "escrow_payment_orders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    payer_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    payee_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    amount_minor = Column(BigInteger, nullable=False)
    currency = Column(String(3), nullable=False, default="IRR")
    provider_code = Column(String(32), nullable=False, default="wallet")
    external_ref = Column(String(64), nullable=True)
    status = Column(String(16), nullable=False, default=STATUS_HELD)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ── Schemas ───────────────────────────────────────────────────────────────────
class EscrowCreate(BaseModel):
    payee_earth_id: str
    amount_minor:   int = Field(..., gt=0)
    currency:       str = "IRR"
    provider_code:  Optional[str] = None


class OrderOut(BaseModel):
    id:              str
    payer_earth_id:  str
    payee_earth_id:  str
    amount_minor:    int
    currency:        str
    provider_code:   str
    external_ref:    Optional[str]
    status:          str
    created_at:      datetime


async def _earth_ids(db: AsyncSession, ids) -> dict:
    ids = {i for i in ids if i}
    if not ids:
        return {}
    return {
        uid: eid for uid, eid in (await db.execute(
            select(User.id, User.earth_id).where(User.id.in_(ids))
        )).all()
    }


def _out(o: PaymentOrder, earth: dict) -> OrderOut:
    return OrderOut(
        id=str(o.id), payer_earth_id=earth.get(o.payer_id, ""),
        payee_earth_id=earth.get(o.payee_id, ""),
        amount_minor=int(o.amount_minor), currency=o.currency,
        provider_code=o.provider_code, external_ref=o.external_ref,
        status=o.status, created_at=o.created_at,
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/escrow", response_model=OrderOut, status_code=201)
async def create_escrow(
    body: EscrowCreate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    payee = (await db.execute(
        select(User).where(User.earth_id == body.payee_earth_id.strip())
    )).scalar_one_or_none()
    if payee is None:
        raise HTTPException(status_code=404, detail="گیرنده یافت نشد")
    if payee.id == me.id:
        raise HTTPException(status_code=400, detail="گیرنده نمی‌تواند خودتان باشد")
    if (body.currency or "IRR").upper() != "IRR":
        raise HTTPException(status_code=400, detail="فعلاً فقط ریال پشتیبانی می‌شود")

    o = PaymentOrder(
        payer_id=me.id, payee_id=payee.id, amount_minor=body.amount_minor,
        currency="IRR", provider_code="wallet",
        external_ref=f"ESC-{_uuid.uuid4().hex[:12].upper()}", status=STATUS_HELD,
    )
    db.add(o)
    await db.flush()

    await lock_escrow(
        db, me.id, body.amount_minor,
        description=f"بلوکهٔ پرداختِ امانی به {payee.earth_id}",
        reference_id=str(o.id),
    )
    await db.commit()
    await db.refresh(o)
    return _out(o, {me.id: me.earth_id, payee.id: payee.earth_id})


@router.get("/escrow", response_model=List[OrderOut])
async def my_escrows(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(PaymentOrder)
        .where(or_(PaymentOrder.payer_id == me.id, PaymentOrder.payee_id == me.id))
        .order_by(PaymentOrder.created_at.desc())
    )).scalars().all()
    earth = await _earth_ids(db, [r.payer_id for r in rows] + [r.payee_id for r in rows])
    return [_out(r, earth) for r in rows]


async def _locked_order(db: AsyncSession, order_id: str) -> PaymentOrder:
    try:
        oid = _uuid.UUID(order_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="شناسهٔ سفارش نامعتبر است")
    o = (await db.execute(
        select(PaymentOrder).where(PaymentOrder.id == oid).with_for_update()
    )).scalar_one_or_none()
    if o is None:
        raise HTTPException(status_code=404, detail="سفارش یافت نشد")
    return o


@router.post("/{order_id}/capture", response_model=OrderOut)
async def capture(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    o = await _locked_order(db, order_id)
    if me.id not in (o.payer_id, o.payee_id):
        raise HTTPException(status_code=403, detail="دسترسی ندارید")
    if o.status != STATUS_HELD:
        raise HTTPException(status_code=409, detail="این سفارش دیگر امانی نیست")

    await release_escrow(
        db, o.payer_id, o.payee_id, int(o.amount_minor),
        out_desc="تسویهٔ پرداختِ امانی", in_desc="دریافتِ پرداختِ امانی",
        reference_id=str(o.id),
    )
    o.status = STATUS_CAPTURED
    await db.commit()
    await db.refresh(o)
    earth = await _earth_ids(db, [o.payer_id, o.payee_id])
    return _out(o, earth)


@router.post("/{order_id}/refund", response_model=OrderOut)
async def refund(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    o = await _locked_order(db, order_id)
    # فقط گیرنده می‌تواند برگرداند؛ وگرنه تضمینی برای او باقی نمی‌ماند.
    if o.payee_id != me.id:
        raise HTTPException(status_code=403, detail="فقط گیرنده می‌تواند وجه را برگرداند")
    if o.status != STATUS_HELD:
        raise HTTPException(status_code=409, detail="این سفارش دیگر امانی نیست")

    await refund_escrow(
        db, o.payer_id, int(o.amount_minor),
        description="بازگشتِ پرداختِ امانی", reference_id=str(o.id),
    )
    o.status = STATUS_REFUNDED
    await db.commit()
    await db.refresh(o)
    earth = await _earth_ids(db, [o.payer_id, o.payee_id])
    return _out(o, earth)
