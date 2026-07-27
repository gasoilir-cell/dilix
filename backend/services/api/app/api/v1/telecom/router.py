"""
Dilix — ارتباطات (Telecom): شارژ/بستهٔ اینترنت و فعال‌سازیِ eSIM

    POST /api/v1/telecom/top-up         شارژِ سیم‌کارت (از کیفِ پول کسر می‌شود)
    POST /api/v1/telecom/esim/activate  فعال‌سازیِ eSIM
    GET  /api/v1/telecom/top-ups        تاریخچهٔ شارژ
    GET  /api/v1/telecom/esims          eSIMهای من

دو تصمیمی که ساختار را تعیین کرد:

۱) **شارژ پیش از ثبت، پول را از کیف کم می‌کند.** اگر سفارش «در انتظار» ثبت
   می‌شد و پول بعداً کم می‌شد، کاربرِ بدونِ موجودی هم می‌توانست صفِ شارژ بسازد.
   نبودِ موجودی همان‌جا خطا می‌دهد و هیچ ردیفی ساخته نمی‌شود.

۲) **`iccid` در سطحِ دیتابیس یکتاست.** دو کاربر نمی‌توانند یک eSIM را فعال
   کنند؛ کنترلِ پایتونی در دو درخواستِ هم‌زمان هر دو را رد می‌کرد.
"""
import re
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, String, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.services.wallet_ops import get_or_create_wallet

router = APIRouter(prefix="/telecom", tags=["Telecom"])

_MSISDN_RE = re.compile(r"^\+?\d{10,15}$")
_ICCID_RE = re.compile(r"^\d{18,22}$")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ref(prefix: str) -> str:
    return f"{prefix}-{_uuid.uuid4().hex[:12].upper()}"


# ── مدل ───────────────────────────────────────────────────────────────────────
class TopUpOrder(Base):
    __tablename__ = "telecom_top_ups"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    msisdn = Column(String(20), nullable=False)
    product_code = Column(String(64), nullable=False)
    amount_minor = Column(BigInteger, nullable=False)
    currency = Column(String(3), nullable=False, default="IRR")
    external_ref = Column(String(64), nullable=True)
    status = Column(String(16), nullable=False, default="completed")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


class EsimProfile(Base):
    __tablename__ = "telecom_esims"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    iccid = Column(String(22), nullable=False, unique=True)
    country_code = Column(String(4), nullable=False, default="IR")
    status = Column(String(16), nullable=False, default="active")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Schemas ───────────────────────────────────────────────────────────────────
class TopUpRequest(BaseModel):
    msisdn:        str
    product_code:  str = Field(..., min_length=1, max_length=64)
    amount_minor:  int = Field(..., gt=0)
    currency:      str = "IRR"
    provider_code: Optional[str] = None   # پذیرفته می‌شود ولی اثری ندارد


class TopUpOut(BaseModel):
    id:           str
    msisdn:       str
    product_code: str
    amount_minor: int
    currency:     str
    status:       str
    external_ref: Optional[str]
    created_at:   datetime

    @classmethod
    def of(cls, o: TopUpOrder) -> "TopUpOut":
        return cls(
            id=str(o.id), msisdn=o.msisdn, product_code=o.product_code,
            amount_minor=int(o.amount_minor), currency=o.currency,
            status=o.status, external_ref=o.external_ref, created_at=o.created_at,
        )


class EsimRequest(BaseModel):
    iccid:         str
    country_code:  str = Field("IR", min_length=2, max_length=4)
    provider_code: Optional[str] = None


class EsimOut(BaseModel):
    id:           str
    iccid:        str
    country_code: str
    status:       str
    created_at:   datetime

    @classmethod
    def of(cls, o: EsimProfile) -> "EsimOut":
        return cls(
            id=str(o.id), iccid=o.iccid, country_code=o.country_code,
            status=o.status, created_at=o.created_at,
        )


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/top-up", response_model=TopUpOut, status_code=201)
async def top_up(
    body: TopUpRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    msisdn = body.msisdn.strip().replace(" ", "")
    if not _MSISDN_RE.match(msisdn):
        raise HTTPException(status_code=400, detail="شمارهٔ موبایل معتبر نیست")
    if (body.currency or "IRR").upper() != "IRR":
        raise HTTPException(status_code=400, detail="فعلاً فقط شارژ به ریال ممکن است")

    await get_or_create_wallet(db, me.id)
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == me.id).with_for_update()
    )).scalar_one()
    if w.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    if w.balance_available < body.amount_minor:
        raise HTTPException(status_code=400, detail="موجودیِ کیفِ پول کافی نیست")

    order = TopUpOrder(
        user_id=me.id, msisdn=msisdn, product_code=body.product_code.strip(),
        amount_minor=body.amount_minor, currency="IRR",
        external_ref=_ref("TOP"), status="completed",
    )
    db.add(order)
    await db.flush()

    before = w.balance_available
    w.balance_available -= body.amount_minor
    db.add(WalletTransaction(
        wallet_id=w.id, type="transfer_out", status="completed",
        amount=body.amount_minor, balance_before=before,
        balance_after=w.balance_available, reference_id=str(order.id),
        description=f"شارژِ {msisdn} ({order.product_code})",
    ))

    await db.commit()
    await db.refresh(order)
    return TopUpOut.of(order)


@router.get("/top-ups", response_model=List[TopUpOut])
async def my_top_ups(
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(TopUpOrder).where(TopUpOrder.user_id == me.id)
        .order_by(TopUpOrder.created_at.desc()).limit(max(1, min(limit, 200)))
    )).scalars().all()
    return [TopUpOut.of(o) for o in rows]


@router.post("/esim/activate", response_model=EsimOut, status_code=201)
async def activate_esim(
    body: EsimRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    iccid = body.iccid.strip().replace(" ", "")
    if not _ICCID_RE.match(iccid):
        raise HTTPException(status_code=400, detail="ICCID معتبر نیست (۱۸ تا ۲۲ رقم)")

    profile = EsimProfile(
        user_id=me.id, iccid=iccid,
        country_code=body.country_code.strip().upper(), status="active",
    )
    db.add(profile)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="این ICCID قبلاً فعال شده است")
    await db.refresh(profile)
    return EsimOut.of(profile)


@router.get("/esims", response_model=List[EsimOut])
async def my_esims(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(EsimProfile).where(EsimProfile.user_id == me.id)
        .order_by(EsimProfile.created_at.desc())
    )).scalars().all()
    return [EsimOut.of(o) for o in rows]
