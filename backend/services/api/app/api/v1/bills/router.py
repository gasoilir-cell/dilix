"""
Dilix — قبوض و خدماتِ شهری (Bills & City Services)

    GET    /api/v1/bills/types              کاتالوگِ انواعِ قبض
    POST   /api/v1/bills/inquiry            استعلامِ قبض از روی شناسه‌ها یا بارکد
    POST   /api/v1/bills/pay                پرداختِ قبض از کیفِ پول
    GET    /api/v1/bills                    تاریخچهٔ پرداخت‌های من
    GET    /api/v1/bills/{payment_ref}      رسیدِ یک پرداخت
    GET    /api/v1/bills/saved              قبض‌های ذخیره‌شده (شناسهٔ ثابتِ اشتراک)
    POST   /api/v1/bills/saved              ذخیرهٔ یک شناسهٔ قبض با نامِ دلخواه
    DELETE /api/v1/bills/saved/{id}         حذفِ قبضِ ذخیره‌شده

چرا اعتبارسنجیِ محلی؟
    «شناسهٔ قبض» و «شناسهٔ پرداخت» ایرانی رقمِ کنترلی دارند و مبلغ و نوعِ
    سازمان **داخلِ خودِ شناسهٔ پرداخت کدگذاری شده‌اند**. پس استعلام بدونِ هیچ
    سرویسِ بیرونی و به‌صورت قطعی قابلِ محاسبه است؛ این یعنی مبلغِ نمایش‌داده‌شده
    ساختگی نیست، از خودِ قبض بیرون کشیده شده است.

مبالغ مثل بقیهٔ کیف‌پول در **ریال** (واحدِ خرد) نگهداری می‌شوند.
"""
import random
import string
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, String, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction

router = APIRouter(prefix="/bills", tags=["Bills"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class BillPayment(Base):
    """رسیدِ پرداختِ یک قبض.

    زوجِ (`bill_id`, `payment_id`) یکتاست: هر قبض فقط **یک‌بار** — آن هم در کلِ
    پلتفرم، نه فقط برای یک کاربر — قابلِ پرداخت است، وگرنه دو نفر می‌توانستند
    هم‌زمان یک قبض را بپردازند و پولِ دومی بی‌جهت می‌رفت.
    """
    __tablename__ = "bill_payments"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref        = Column(String(20), unique=True, nullable=False)     # کدِ رهگیریِ نمایشی
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    bill_id    = Column(String(13), nullable=False)
    payment_id = Column(String(13), nullable=False)
    bill_type  = Column(String(16), nullable=False, default="other")  # کلیدِ BILL_TYPES
    amount     = Column(BigInteger, nullable=False)                   # ریال
    title      = Column(String(120), nullable=True)                   # نامِ دلخواهِ کاربر
    paid_at    = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_bill_payment", "bill_id", "payment_id", unique=True),
        Index("ix_bill_payment_user", "user_id", "paid_at"),
    )


class SavedBill(Base):
    """شناسهٔ قبضِ ذخیره‌شده (مثلِ «برقِ خانه»).

    فقط `bill_id` ذخیره می‌شود چون در قبوضِ ایرانی شناسهٔ قبض برای هر اشتراک
    **ثابت** است و فقط شناسهٔ پرداخت هر دوره عوض می‌شود.
    """
    __tablename__ = "saved_bills"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title      = Column(String(120), nullable=False)
    bill_id    = Column(String(13), nullable=False)
    bill_type  = Column(String(16), nullable=False, default="other")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_saved_bill", "user_id", "bill_id", unique=True),
    )


# ── کاتالوگِ انواعِ قبض ────────────────────────────────────────────────────────
# کلید = رقمِ یکی‌مانده‌به‌آخرِ «شناسهٔ قبض»؛ این نگاشت استانداردِ کشوری است و
# سازمانِ صادرکننده را مشخص می‌کند.
BILL_TYPES = {
    "1": {"key": "water",     "label": "آب",                    "emoji": "💧"},
    "2": {"key": "power",     "label": "برق",                   "emoji": "⚡"},
    "3": {"key": "gas",       "label": "گاز",                   "emoji": "🔥"},
    "4": {"key": "telecom",   "label": "تلفنِ ثابت",             "emoji": "☎️"},
    "5": {"key": "mobile",    "label": "تلفنِ همراه",            "emoji": "📱"},
    "6": {"key": "municipal", "label": "عوارضِ شهرداری",         "emoji": "🏙"},
    "7": {"key": "driving",   "label": "جریمهٔ راهنمایی‌ورانندگی", "emoji": "🚦"},
    "8": {"key": "tax",       "label": "مالیات",                "emoji": "🧾"},
    "9": {"key": "other",     "label": "سایر",                  "emoji": "📄"},
}
_UNKNOWN_TYPE = {"key": "other", "label": "سایر", "emoji": "📄"}

BILL_MIN_AMOUNT = 1_000            # کف: ۱۰۰ تومان
BILL_MAX_AMOUNT = 5_000_000_000    # سقف: ۵۰۰٬۰۰۰٬۰۰۰ تومان


# ── الگوریتمِ رقمِ کنترلی ──────────────────────────────────────────────────────
def _check_digit(digits: str) -> int:
    """رقمِ کنترلیِ استانداردِ قبوضِ ایران.

    وزن‌های ۲ تا ۷ به‌صورتِ چرخشی از راست‌ترین رقم به چپ اعمال، جمع بر ۱۱
    باقی‌مانده‌گیری، و اگر باقی‌مانده کمتر از ۲ بود رقمِ کنترلی صفر است.
    """
    total = 0
    weight = 2
    for ch in reversed(digits):
        total += int(ch) * weight
        weight = 2 if weight == 7 else weight + 1
    r = total % 11
    return 0 if r < 2 else 11 - r


# ارقامِ فارسی «۰-۹» و عربیِ «٠-٩» → لاتین. کاربر شناسه را از روی قبضِ کاغذی
# تایپ می‌کند، پس رقمِ فارسی و فاصله و خط‌تیره عادی است و نباید خطا بدهد.
_DIGIT_MAP = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def _normalize(raw: str) -> str:
    """فقط ارقامِ لاتینِ ورودی را برمی‌گرداند."""
    return "".join(ch for ch in (raw or "").translate(_DIGIT_MAP) if ch in "0123456789")


class DecodedBill(BaseModel):
    bill_id: str
    payment_id: str
    type_key: str
    type_label: str
    type_emoji: str
    amount: int                       # ریال
    year: Optional[int] = None        # رقمِ سالِ صدور (یکانِ سالِ شمسی)
    period: Optional[int] = None      # دورهٔ قبض


def _decode(bill_id: str, payment_id: str) -> DecodedBill:
    """اعتبارسنجی و رمزگشاییِ زوجِ شناسه؛ در صورتِ نامعتبر بودن HTTPException."""
    bill_id = _normalize(bill_id)
    payment_id = _normalize(payment_id)

    if not (6 <= len(bill_id) <= 13):
        raise HTTPException(400, detail="شناسهٔ قبض باید بینِ ۶ تا ۱۳ رقم باشد")
    if not (6 <= len(payment_id) <= 13):
        raise HTTPException(400, detail="شناسهٔ پرداخت باید بینِ ۶ تا ۱۳ رقم باشد")

    # ۱) رقمِ کنترلیِ خودِ شناسهٔ قبض
    if _check_digit(bill_id[:-1]) != int(bill_id[-1]):
        raise HTTPException(400, detail="شناسهٔ قبض معتبر نیست")
    # ۲) رقمِ کنترلیِ خودِ شناسهٔ پرداخت
    if _check_digit(payment_id[:-2]) != int(payment_id[-2]):
        raise HTTPException(400, detail="شناسهٔ پرداخت معتبر نیست")
    # ۳) رقمِ کنترلیِ پیوندِ دو شناسه — همین رقم است که جلوی جفت‌کردنِ شناسهٔ
    #    پرداختِ یک قبض با شناسهٔ قبضِ دیگری را می‌گیرد. مشخصات می‌گوید صفرهای
    #    سمتِ چپِ هر شناسه پیش از چسباندن حذف شوند، اما پیاده‌سازی‌های رایج این
    #    کار را نمی‌کنند؛ چون هر دو در عمل دیده می‌شوند و ردِ یک قبضِ واقعی از
    #    پذیرشِ یک حالتِ اضافه بدتر است، هر دو صورت پذیرفته می‌شود. وقتی شناسه‌ها
    #    صفرِ ابتدایی ندارند — یعنی حالتِ متداول — این دو یکی‌اند.
    linked = {
        _check_digit(bill_id + payment_id[:-1]),
        _check_digit(bill_id.lstrip("0") + payment_id[:-1].lstrip("0")),
    }
    if int(payment_id[-1]) not in linked:
        raise HTTPException(400, detail="شناسهٔ پرداخت با این شناسهٔ قبض هم‌خوان نیست")

    amount = int(payment_id[:-5] or 0) * 1_000        # پنج رقمِ آخر مبلغ نیستند
    if amount < BILL_MIN_AMOUNT:
        raise HTTPException(400, detail="مبلغِ این قبض معتبر نیست")
    if amount > BILL_MAX_AMOUNT:
        raise HTTPException(400, detail="مبلغِ این قبض از سقفِ مجاز بیشتر است")

    kind = BILL_TYPES.get(bill_id[-2], _UNKNOWN_TYPE)
    return DecodedBill(
        bill_id=bill_id,
        payment_id=payment_id,
        type_key=kind["key"],
        type_label=kind["label"],
        type_emoji=kind["emoji"],
        amount=amount,
        year=int(payment_id[-5]),
        period=int(payment_id[-4:-2]),
    )


def _ref() -> str:
    return "BL" + "".join(random.choices(string.digits, k=10))


# ── Schemas ──────────────────────────────────────────────────────────────────
class BillTypeOut(BaseModel):
    key: str
    label: str
    emoji: str
    org_digit: str


class InquiryIn(BaseModel):
    """یا زوجِ شناسه بده، یا `barcode` (۲۶ رقمِ به‌هم‌چسبیده روی قبض)."""
    bill_id: Optional[str] = None
    payment_id: Optional[str] = None
    barcode: Optional[str] = None


class InquiryOut(DecodedBill):
    already_paid: bool = False
    paid_ref: Optional[str] = None
    balance_enough: bool = True


class PayIn(InquiryIn):
    title: Optional[str] = Field(None, max_length=120)


class ReceiptOut(BaseModel):
    id: str
    ref: str
    bill_id: str
    payment_id: str
    type_key: str
    type_label: str
    type_emoji: str
    amount: int
    title: Optional[str] = None
    paid_at: datetime


class SavedBillIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    bill_id: str


class SavedBillOut(BaseModel):
    id: str
    title: str
    bill_id: str
    type_key: str
    type_label: str
    type_emoji: str
    created_at: datetime


def _split(payload: InquiryIn) -> tuple[str, str]:
    """زوجِ شناسه را از بدنه بیرون می‌کشد؛ بارکد را نصف می‌کند.

    بارکدِ چاپ‌شده روی قبض دقیقاً ۲۶ رقم است: ۱۳ رقمِ شناسهٔ قبض و ۱۳ رقمِ
    شناسهٔ پرداخت، بدونِ هیچ جداکننده‌ای.
    """
    if payload.barcode:
        code = _normalize(payload.barcode)
        if len(code) != 26:
            raise HTTPException(400, detail="بارکدِ قبض باید ۲۶ رقم باشد")
        return code[:13], code[13:]
    if not payload.bill_id or not payload.payment_id:
        raise HTTPException(400, detail="شناسهٔ قبض و شناسهٔ پرداخت الزامی است")
    return payload.bill_id, payload.payment_id


def _type_of(bill_id: str) -> dict:
    return BILL_TYPES.get(bill_id[-2], _UNKNOWN_TYPE) if len(bill_id) >= 2 else _UNKNOWN_TYPE


def _receipt(b: BillPayment) -> ReceiptOut:
    kind = _type_of(b.bill_id)
    return ReceiptOut(
        id=str(b.id), ref=b.ref, bill_id=b.bill_id, payment_id=b.payment_id,
        type_key=kind["key"], type_label=kind["label"], type_emoji=kind["emoji"],
        amount=b.amount, title=b.title, paid_at=b.paid_at,
    )


# ── Endpoints ────────────────────────────────────────────────────────────────
@router.get("/types", response_model=List[BillTypeOut])
async def bill_types():
    """کاتالوگِ سازمان‌های صادرکنندهٔ قبض (عمومی، بدونِ نیاز به توکن)."""
    return [BillTypeOut(org_digit=d, **v) for d, v in BILL_TYPES.items()]


@router.post("/inquiry", response_model=InquiryOut)
async def inquiry(
    payload: InquiryIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """استعلامِ قبض: اعتبارسنجیِ شناسه‌ها + مبلغ + وضعیتِ پرداخت‌شدگی."""
    bill_id, payment_id = _split(payload)
    d = _decode(bill_id, payment_id)

    prev = (await db.execute(
        select(BillPayment).where(
            BillPayment.bill_id == d.bill_id,
            BillPayment.payment_id == d.payment_id,
        )
    )).scalar_one_or_none()

    w = (await db.execute(select(Wallet).where(Wallet.user_id == me.id))).scalar_one_or_none()
    balance = w.balance_available if w else 0

    return InquiryOut(
        **d.model_dump(),
        already_paid=prev is not None,
        paid_ref=prev.ref if prev else None,
        balance_enough=balance >= d.amount,
    )


@router.post("/pay", response_model=ReceiptOut)
async def pay_bill(
    payload: PayIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پرداختِ قبض از موجودیِ کیفِ پول."""
    bill_id, payment_id = _split(payload)
    d = _decode(bill_id, payment_id)

    # پیش‌بررسیِ ارزان تا در حالتِ عادی سراغِ قفلِ کیف نرویم.
    prev = (await db.execute(
        select(BillPayment).where(
            BillPayment.bill_id == d.bill_id,
            BillPayment.payment_id == d.payment_id,
        )
    )).scalar_one_or_none()
    if prev is not None:
        raise HTTPException(409, detail="این قبض قبلاً پرداخت شده است")

    # قفلِ ردیفِ کیف‌پول تا دو پرداختِ هم‌زمان هر دو همان موجودی را نخوانند.
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == me.id).with_for_update()
    )).scalar_one_or_none()
    if w is None:
        raise HTTPException(400, detail="موجودی کافی نیست")
    if w.is_frozen:
        raise HTTPException(403, detail="کیف‌پول مسدود است")
    if w.balance_available < d.amount:
        raise HTTPException(400, detail="موجودی کافی نیست")

    before = w.balance_available
    w.balance_available -= d.amount
    bill = BillPayment(
        ref=_ref(), user_id=me.id, bill_id=d.bill_id, payment_id=d.payment_id,
        bill_type=d.type_key, amount=d.amount,
        title=(payload.title or "").strip() or None,
    )
    db.add(bill)
    db.add(WalletTransaction(
        wallet_id=w.id, type="withdrawal", status="completed",
        amount=d.amount, balance_before=before, balance_after=w.balance_available,
        reference_id=bill.ref,
        description=f"پرداختِ قبضِ {d.type_label} {d.type_emoji}",
        metadata_={"bill_id": d.bill_id, "payment_id": d.payment_id, "bill_type": d.type_key},
    ))

    try:
        await db.commit()
    except Exception:
        # ایندکسِ یکتا برندهٔ مسابقهٔ دو پرداختِ هم‌زمان را تعیین می‌کند؛ بازندهٔ
        # مسابقه نباید پولش کم شود، پس کلِ تراکنش برمی‌گردد.
        await db.rollback()
        raise HTTPException(409, detail="این قبض قبلاً پرداخت شده است")

    await db.refresh(bill)
    return _receipt(bill)


@router.get("/saved", response_model=List[SavedBillOut])
async def list_saved(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(SavedBill).where(SavedBill.user_id == me.id)
        .order_by(SavedBill.created_at.desc())
    )).scalars().all()
    out = []
    for s in rows:
        kind = _type_of(s.bill_id)
        out.append(SavedBillOut(
            id=str(s.id), title=s.title, bill_id=s.bill_id,
            type_key=kind["key"], type_label=kind["label"], type_emoji=kind["emoji"],
            created_at=s.created_at,
        ))
    return out


@router.post("/saved", response_model=SavedBillOut, status_code=201)
async def save_bill(
    payload: SavedBillIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ذخیرهٔ شناسهٔ قبضِ یک اشتراک برای استعلامِ سریعِ دوره‌های بعد."""
    bill_id = _normalize(payload.bill_id)
    if not (6 <= len(bill_id) <= 13) or _check_digit(bill_id[:-1]) != int(bill_id[-1]):
        raise HTTPException(400, detail="شناسهٔ قبض معتبر نیست")

    dup = (await db.execute(
        select(SavedBill).where(SavedBill.user_id == me.id, SavedBill.bill_id == bill_id)
    )).scalar_one_or_none()
    if dup is not None:
        raise HTTPException(409, detail="این شناسه قبلاً ذخیره شده است")

    kind = _type_of(bill_id)
    s = SavedBill(
        user_id=me.id, title=payload.title.strip(),
        bill_id=bill_id, bill_type=kind["key"],
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return SavedBillOut(
        id=str(s.id), title=s.title, bill_id=s.bill_id,
        type_key=kind["key"], type_label=kind["label"], type_emoji=kind["emoji"],
        created_at=s.created_at,
    )


@router.delete("/saved/{saved_id}", status_code=204)
async def delete_saved(
    saved_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        sid = _uuid.UUID(saved_id)
    except ValueError:
        raise HTTPException(404, detail="یافت نشد")
    s = (await db.execute(
        select(SavedBill).where(SavedBill.id == sid, SavedBill.user_id == me.id)
    )).scalar_one_or_none()
    if s is None:
        raise HTTPException(404, detail="یافت نشد")
    await db.delete(s)
    await db.commit()


@router.get("", response_model=List[ReceiptOut])
async def my_bills(
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(BillPayment).where(BillPayment.user_id == me.id)
        .order_by(BillPayment.paid_at.desc()).limit(limit).offset(offset)
    )).scalars().all()
    return [_receipt(b) for b in rows]


@router.get("/{payment_ref}", response_model=ReceiptOut)
async def bill_receipt(
    payment_ref: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    b = (await db.execute(
        select(BillPayment).where(
            BillPayment.ref == payment_ref, BillPayment.user_id == me.id
        )
    )).scalar_one_or_none()
    if b is None:
        raise HTTPException(404, detail="رسید یافت نشد")
    return _receipt(b)
