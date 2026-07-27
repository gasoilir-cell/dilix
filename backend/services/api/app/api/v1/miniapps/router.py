"""
Dilix — Mini Program SDK — فاز ۴ (اکوسیستم)

میزبان (کاربرِ لاگین‌کرده):
    GET    /api/v1/miniapps                    فهرستِ برنامه‌های تأییدشده
    GET    /api/v1/miniapps/mine               برنامه‌هایی که خودم ساخته‌ام
    GET    /api/v1/miniapps/installed          برنامه‌های نصب‌شدهٔ من
    POST   /api/v1/miniapps                    ساختِ برنامه (کلیدِ مخفی یک‌بار)
    PATCH  /api/v1/miniapps/{app_id}           ویرایش
    POST   /api/v1/miniapps/{app_id}/submit    ارسال برای بازبینی
    POST   /api/v1/miniapps/{app_id}/secret    چرخشِ کلیدِ مخفی
    POST   /api/v1/miniapps/{app_id}/review    تأیید/ردِ مدیر
    GET    /api/v1/miniapps/{app_id}           جزئیات
    POST   /api/v1/miniapps/{app_id}/install   نصب (اعطای دسترسی‌ها)
    DELETE /api/v1/miniapps/{app_id}/install   حذفِ نصب
    POST   /api/v1/miniapps/{app_id}/launch    اجرا → کدِ یک‌بارمصرف + آدرس
    GET    /api/v1/miniapps/payments/pending   پرداخت‌های منتظرِ تأییدِ من
    POST   /api/v1/miniapps/payments/{ref}/confirm  پرداخت
    POST   /api/v1/miniapps/payments/{ref}/cancel   رد

SDK (خودِ برنامه، با کلیدِ مخفی — بدونِ توکنِ کاربر):
    POST   /api/v1/miniapps/sdk/session        code → توکنِ نشست
    GET    /api/v1/miniapps/sdk/me             هویتِ مستعارِ کاربر
    POST   /api/v1/miniapps/sdk/pay            *درخواستِ* پرداخت
    GET    /api/v1/miniapps/sdk/pay/{ref}      وضعیتِ پرداخت

سه تصمیمی که ساختار را تعیین کرد:

۱) **هویتِ مستعارِ هر برنامه (`open_id`)** — برنامه هرگز `earth_id` یا شناسهٔ
   واقعیِ کاربر را نمی‌بیند. `open_id` از HMACِ (شناسهٔ برنامه + شناسهٔ کاربر)
   ساخته می‌شود: درونِ یک برنامه پایدار است، اما دو برنامه نمی‌توانند با
   مقایسهٔ شناسه‌ها بفهمند کاربرشان یکی است.

۲) **برنامه نمی‌تواند پول بردارد، فقط می‌تواند درخواست کند.** پرداختِ ساخته‌شده
   با SDK در وضعیتِ `pending` می‌ماند و تنها **کاربر** در خودِ دیلیکس آن را
   تأیید می‌کند. در غیرِ این صورت لو رفتنِ کلیدِ مخفیِ یک برنامه یعنی خالی‌شدنِ
   کیفِ همهٔ کاربرانش.

۳) **دسترسی‌ها هنگامِ نصب snapshot می‌شوند.** اگر برنامه بعداً دسترسیِ تازه‌ای
   به فهرستش اضافه کند، نصب‌های قبلی آن را نمی‌گیرند و برنامه دوباره به
   بازبینی می‌رود؛ وگرنه کاربر چیزی را می‌داد که هرگز به آن رضایت نداده بود.
"""
import hashlib
import hmac
import secrets
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, Integer, String, Text,
    UniqueConstraint, func, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.database import Base, get_db
from app.core.security import decode_token
from app.models.user import User
from app.services.wallet_ops import move_money

from jose import jwt

router = APIRouter(prefix="/miniapps", tags=["MiniApps"])

# کارمزدِ پلتفرم روی پرداختِ درون‌برنامه — همان نرخِ فروشگاه، تا دو مسیرِ پولی
# دو نرخِ متفاوت نداشته باشند.
COMMISSION_PCT = 2

AUTH_CODE_TTL_SECONDS = 300          # کدِ اجرا کوتاه‌عمر است
SESSION_TTL_SECONDS = 3600           # توکنِ نشستِ برنامه
PAYMENT_TTL_MINUTES = 15
PAY_MIN = 1_000
PAY_MAX = 500_000_000

# دسترسی‌های شناخته‌شده. هر چیزِ خارج از این مجموعه رد می‌شود تا برنامه نتواند
# با نامِ دلخواه دسترسیِ نامفهوم از کاربر بگیرد.
SCOPES = {
    "profile": "نام و تصویرِ نمایشی",
    "payment": "درخواستِ پرداخت از کیفِ پول",
    "location": "کشور و زبانِ کاربر",
}

CATEGORIES = ("tools", "games", "shopping", "finance", "travel", "food",
              "education", "health", "social", "other")

STATUS_LABEL = {
    "draft": "پیش‌نویس",
    "pending": "در انتظارِ بازبینی",
    "approved": "تأییدشده",
    "rejected": "ردشده",
    "suspended": "معلق",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class MiniApp(Base):
    """یک برنامهٔ کوچک. `secret_hash` فقط هشِ کلید است — کلیدِ خام هرگز ذخیره
    نمی‌شود و تنها یک‌بار (هنگامِ ساخت یا چرخش) به سازنده نشان داده می‌شود."""
    __tablename__ = "mini_apps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    app_id = Column(String(24), nullable=False, unique=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    name = Column(String(80), nullable=False)
    tagline = Column(String(160), nullable=True)
    description = Column(Text, nullable=True)
    icon_url = Column(String(500), nullable=True)
    entry_url = Column(String(500), nullable=False)
    category = Column(String(20), nullable=False, default="other")
    scopes = Column(String(200), nullable=False, default="profile")
    secret_hash = Column(String(64), nullable=False)
    status = Column(String(16), nullable=False, default="draft")
    review_note = Column(Text, nullable=True)
    install_count = Column(Integer, nullable=False, default=0)
    open_count = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("ix_mini_app_owner", "owner_id"),
        Index("ix_mini_app_status", "status", "category"),
    )


class MiniAppInstall(Base):
    """نصبِ یک برنامه برای یک کاربر.

    `auth_code` روی همین ردیف می‌نشیند چون کد ذاتاً متعلق به همین جفت
    (برنامه، کاربر) است؛ اجرای دوباره کدِ قبلی را باطل می‌کند و تبادلِ موفق
    آن را پاک می‌کند — پس کد هم یک‌بارمصرف است هم کوتاه‌عمر.
    """
    __tablename__ = "mini_app_installs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    app_uid = Column(UUID(as_uuid=True), ForeignKey("mini_apps.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    open_id = Column(String(64), nullable=False)
    scopes = Column(String(200), nullable=False, default="")
    auth_code = Column(String(64), nullable=True)
    auth_code_expires = Column(DateTime(timezone=True), nullable=True)
    installed_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    last_open_at = Column(DateTime(timezone=True), nullable=True)
    open_count = Column(Integer, nullable=False, default=0)

    __table_args__ = (
        UniqueConstraint("app_uid", "user_id", name="uq_mini_install_pair"),
        Index("ix_mini_install_user", "user_id"),
    )


class MiniAppPayment(Base):
    """درخواستِ پرداختِ یک برنامه از یک کاربر.

    `out_trade_no` شناسهٔ سفارشِ خودِ برنامه است و با `app_uid` یکتاست: اگر
    درخواستِ ناموفق دوباره فرستاده شود، همان ردیفِ قبلی برمی‌گردد نه یک
    بدهیِ تازه.
    """
    __tablename__ = "mini_app_payments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref = Column(String(24), nullable=False, unique=True)
    app_uid = Column(UUID(as_uuid=True), ForeignKey("mini_apps.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    out_trade_no = Column(String(64), nullable=False)
    subject = Column(String(160), nullable=False)
    amount = Column(BigInteger, nullable=False)
    commission = Column(BigInteger, nullable=False, default=0)
    status = Column(String(16), nullable=False, default="pending")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    paid_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        UniqueConstraint("app_uid", "out_trade_no", name="uq_mini_pay_trade"),
        Index("ix_mini_pay_user", "user_id", "status"),
    )


# ── طرح‌ها ────────────────────────────────────────────────────────────────────
class AppIn(BaseModel):
    name: str = Field(..., min_length=2, max_length=80)
    entry_url: str = Field(..., min_length=8, max_length=500)
    tagline: Optional[str] = Field(None, max_length=160)
    description: Optional[str] = Field(None, max_length=4000)
    icon_url: Optional[str] = Field(None, max_length=500)
    category: str = Field("other", max_length=20)
    scopes: List[str] = Field(default_factory=lambda: ["profile"])


class AppPatch(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=80)
    entry_url: Optional[str] = Field(None, min_length=8, max_length=500)
    tagline: Optional[str] = Field(None, max_length=160)
    description: Optional[str] = Field(None, max_length=4000)
    icon_url: Optional[str] = Field(None, max_length=500)
    category: Optional[str] = Field(None, max_length=20)
    scopes: Optional[List[str]] = None


class AppOut(BaseModel):
    app_id: str
    name: str
    tagline: Optional[str] = None
    description: Optional[str] = None
    icon_url: Optional[str] = None
    entry_url: Optional[str] = None      # فقط برای سازنده/نصب‌کننده
    category: str
    scopes: List[str]
    status: str
    status_label: str
    review_note: Optional[str] = None
    install_count: int
    open_count: int
    owner_earth_id: str
    owner_name: Optional[str] = None
    is_mine: bool = False
    is_installed: bool = False
    installed_scopes: List[str] = Field(default_factory=list)
    # وقتی برنامه دسترسیِ تازه‌ای خواسته که کاربر هنوز نداده، کلاینت باید
    # صفحهٔ رضایتِ دوباره نشان دهد نه اینکه بی‌صدا اجرا کند.
    needs_reconsent: bool = False
    created_at: datetime


class AppCreated(AppOut):
    app_secret: str      # فقط همین یک‌بار


class LaunchOut(BaseModel):
    app_id: str
    url: str             # entry_url + ?code=...&app_id=...
    code: str
    expires_in: int


class InstallIn(BaseModel):
    scopes: Optional[List[str]] = None    # پیش‌فرض: همهٔ دسترسی‌های خواسته‌شده


class ReviewIn(BaseModel):
    approve: bool
    note: Optional[str] = Field(None, max_length=500)


class SessionIn(BaseModel):
    app_id: str
    app_secret: str
    code: str


class SessionOut(BaseModel):
    session_token: str
    open_id: str
    scopes: List[str]
    expires_in: int


class SdkMeOut(BaseModel):
    open_id: str
    scopes: List[str]
    name: Optional[str] = None
    avatar_url: Optional[str] = None
    country_code: Optional[str] = None
    locale: Optional[str] = None


class PayIn(BaseModel):
    amount: int = Field(..., ge=PAY_MIN, le=PAY_MAX)
    subject: str = Field(..., min_length=2, max_length=160)
    out_trade_no: str = Field(..., min_length=1, max_length=64)


class PaymentOut(BaseModel):
    ref: str
    app_id: str
    app_name: str
    app_icon: Optional[str] = None
    out_trade_no: str
    subject: str
    amount: int
    commission: int
    status: str
    created_at: datetime
    expires_at: datetime
    paid_at: Optional[datetime] = None


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _open_id(app_uid, user_id) -> str:
    """هویتِ مستعارِ پایدارِ کاربر **درونِ یک برنامه**.

    HMAC است نه هشِ ساده، چون بدونِ کلید هر کسی می‌توانست با داشتنِ شناسهٔ
    کاربر همان مقدار را بسازد و نگاشتِ open_id → کاربر را بیرون بازسازی کند.
    """
    msg = f"{app_uid}:{user_id}".encode()
    return hmac.new(settings.JWT_SECRET.encode(), msg, hashlib.sha256).hexdigest()[:32]


def _hash_secret(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def _split(s: Optional[str]) -> List[str]:
    return [x for x in (s or "").split(",") if x]


def _clean_scopes(items: Optional[List[str]]) -> List[str]:
    out = []
    for s in (items or []):
        s = str(s).strip().lower()
        if s and s not in out:
            if s not in SCOPES:
                raise HTTPException(status_code=400, detail=f"دسترسیِ ناشناخته: {s}")
            out.append(s)
    return out or ["profile"]


async def _app_by_id(db: AsyncSession, app_id: str) -> MiniApp:
    a = (await db.execute(
        select(MiniApp).where(MiniApp.app_id == app_id)
    )).scalar_one_or_none()
    if a is None:
        raise HTTPException(status_code=404, detail="برنامه پیدا نشد")
    return a


async def _my_app(db: AsyncSession, app_id: str, me: User) -> MiniApp:
    a = await _app_by_id(db, app_id)
    if a.owner_id != me.id:
        raise HTTPException(status_code=404, detail="برنامه پیدا نشد")
    return a


async def _install_of(db: AsyncSession, app_uid, user_id) -> Optional[MiniAppInstall]:
    return (await db.execute(
        select(MiniAppInstall).where(
            MiniAppInstall.app_uid == app_uid,
            MiniAppInstall.user_id == user_id,
        )
    )).scalar_one_or_none()


def _app_out(a: MiniApp, owner: Optional[User], me_id,
             install: Optional[MiniAppInstall] = None) -> AppOut:
    is_mine = a.owner_id == me_id
    wanted = _split(a.scopes)
    granted = _split(install.scopes) if install else []
    return AppOut(
        app_id=a.app_id, name=a.name, tagline=a.tagline,
        description=a.description, icon_url=a.icon_url,
        # آدرسِ ورودی فقط به سازنده و نصب‌کننده داده می‌شود؛ فهرستِ عمومی
        # نباید نقشهٔ کاملِ زیرساختِ همهٔ برنامه‌ها باشد.
        entry_url=(a.entry_url if (is_mine or install is not None) else None),
        category=a.category, scopes=wanted,
        status=a.status, status_label=STATUS_LABEL.get(a.status, a.status),
        review_note=(a.review_note if is_mine else None),
        install_count=int(a.install_count), open_count=int(a.open_count),
        owner_earth_id=(owner.earth_id if owner else ""),
        owner_name=((owner.full_name or owner.username or owner.earth_id)
                    if owner else None),
        is_mine=is_mine, is_installed=install is not None,
        installed_scopes=granted,
        needs_reconsent=bool(install is not None
                             and set(wanted) - set(granted)),
        created_at=a.created_at,
    )


def _payment_out(p: MiniAppPayment, a: MiniApp) -> PaymentOut:
    return PaymentOut(
        ref=p.ref, app_id=a.app_id, app_name=a.name, app_icon=a.icon_url,
        out_trade_no=p.out_trade_no, subject=p.subject, amount=int(p.amount),
        commission=int(p.commission), status=p.status,
        created_at=p.created_at, expires_at=p.expires_at, paid_at=p.paid_at,
    )


def _effective_status(p: MiniAppPayment) -> str:
    """انقضای تنبل: درخواستِ سررسیدشده هرگز `pending` گزارش نمی‌شود، حتی اگر
    هیچ حلقهٔ پس‌زمینه‌ای هنوز به آن نرسیده باشد."""
    if p.status == "pending" and p.expires_at and p.expires_at <= _now():
        return "expired"
    return p.status


# ── فهرست/ساخت/ویرایش ────────────────────────────────────────────────────────
@router.get("", response_model=List[AppOut])
async def list_apps(
    q: Optional[str] = Query(None, max_length=100),
    category: Optional[str] = Query(None, max_length=20),
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ویترینِ برنامه‌ها. فقط تأییدشده‌ها — برنامهٔ بازبینی‌نشده نباید در
    فهرستِ عمومی دیده شود."""
    stmt = select(MiniApp).where(MiniApp.status == "approved")
    if category:
        stmt = stmt.where(MiniApp.category == category)
    if q:
        stmt = stmt.where(MiniApp.name.ilike(f"%{q.strip()}%"))
    rows = (await db.execute(
        stmt.order_by(MiniApp.install_count.desc(), MiniApp.created_at.desc())
        .limit(limit).offset(offset)
    )).scalars().all()
    return await _decorate(db, rows, me)


@router.get("/mine", response_model=List[AppOut])
async def my_apps(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(MiniApp).where(MiniApp.owner_id == me.id)
        .order_by(MiniApp.created_at.desc())
    )).scalars().all()
    return await _decorate(db, rows, me)


@router.get("/installed", response_model=List[AppOut])
async def installed_apps(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    installs = (await db.execute(
        select(MiniAppInstall).where(MiniAppInstall.user_id == me.id)
        .order_by(MiniAppInstall.last_open_at.desc().nullslast(),
                  MiniAppInstall.installed_at.desc())
    )).scalars().all()
    if not installs:
        return []
    ids = [i.app_uid for i in installs]
    apps = {a.id: a for a in (await db.execute(
        select(MiniApp).where(MiniApp.id.in_(ids))
    )).scalars().all()}
    owners = await _owners(db, [a.owner_id for a in apps.values()])
    out = []
    for i in installs:
        a = apps.get(i.app_uid)
        if a is not None:
            out.append(_app_out(a, owners.get(a.owner_id), me.id, i))
    return out


async def _owners(db: AsyncSession, ids) -> dict:
    ids = [i for i in set(ids) if i]
    if not ids:
        return {}
    rows = (await db.execute(select(User).where(User.id.in_(ids)))).scalars().all()
    return {u.id: u for u in rows}


async def _decorate(db: AsyncSession, rows: List[MiniApp], me: User) -> List[AppOut]:
    if not rows:
        return []
    owners = await _owners(db, [a.owner_id for a in rows])
    installs = {i.app_uid: i for i in (await db.execute(
        select(MiniAppInstall).where(
            MiniAppInstall.user_id == me.id,
            MiniAppInstall.app_uid.in_([a.id for a in rows]),
        )
    )).scalars().all()}
    return [_app_out(a, owners.get(a.owner_id), me.id, installs.get(a.id))
            for a in rows]


@router.post("", response_model=AppCreated, status_code=201)
async def create_app(
    body: AppIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ساختِ برنامه. کلیدِ مخفی **فقط همین‌جا** برمی‌گردد و پس از آن تنها هشش
    را داریم؛ گم‌شدنش یعنی چرخش، نه بازیابی."""
    if body.category not in CATEGORIES:
        raise HTTPException(status_code=400, detail="دستهٔ نامعتبر")
    entry = body.entry_url.strip()
    if not entry.startswith("https://"):
        # http ساده یعنی کدِ یک‌بارمصرف و توکنِ نشست روی سیم قابلِ شنود است.
        raise HTTPException(status_code=400, detail="آدرسِ ورودی باید https باشد")

    raw_secret = secrets.token_urlsafe(32)
    a = MiniApp(
        app_id="mp_" + secrets.token_hex(8),
        owner_id=me.id, name=body.name.strip(), entry_url=entry,
        tagline=(body.tagline or "").strip() or None,
        description=(body.description or "").strip() or None,
        icon_url=(body.icon_url or "").strip() or None,
        category=body.category,
        scopes=",".join(_clean_scopes(body.scopes)),
        secret_hash=_hash_secret(raw_secret),
        status="draft",
    )
    db.add(a)
    await db.commit()
    await db.refresh(a)
    base = _app_out(a, me, me.id)
    return AppCreated(**base.model_dump(), app_secret=raw_secret)


@router.patch("/{app_id}", response_model=AppOut)
async def update_app(
    app_id: str,
    body: AppPatch,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ویرایش. تغییرِ **ماهوی** (آدرسِ ورودی یا دسترسی‌ها) برنامهٔ تأییدشده را
    دوباره به بازبینی می‌فرستد؛ وگرنه هر برنامه‌ای می‌توانست پس از تأیید
    مقصدش را عوض کند و مُهرِ تأیید بی‌معنا می‌شد."""
    a = await _my_app(db, app_id, me)
    data = body.model_dump(exclude_unset=True)
    material = False

    if "category" in data and data["category"] is not None:
        if data["category"] not in CATEGORIES:
            raise HTTPException(status_code=400, detail="دستهٔ نامعتبر")
    if "entry_url" in data and data["entry_url"]:
        entry = data["entry_url"].strip()
        if not entry.startswith("https://"):
            raise HTTPException(status_code=400, detail="آدرسِ ورودی باید https باشد")
        material = material or entry != a.entry_url
        data["entry_url"] = entry
    if "scopes" in data and data["scopes"] is not None:
        sc = ",".join(_clean_scopes(data["scopes"]))
        material = material or sc != a.scopes
        data["scopes"] = sc

    for k in ("name", "tagline", "description", "icon_url"):
        if k in data and data[k] is not None:
            data[k] = str(data[k]).strip() or None
    for k, v in data.items():
        if v is not None:
            setattr(a, k, v)

    if material and a.status == "approved":
        a.status = "pending"
        a.review_note = "به دلیلِ تغییرِ آدرس یا دسترسی‌ها، بازبینیِ دوباره لازم است"
    await db.commit()
    await db.refresh(a)
    return _app_out(a, me, me.id)


@router.post("/{app_id}/submit", response_model=AppOut)
async def submit_app(
    app_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    a = await _my_app(db, app_id, me)
    if a.status not in ("draft", "rejected"):
        raise HTTPException(status_code=400, detail="این برنامه در وضعیتِ ارسال نیست")
    a.status = "pending"
    a.review_note = None
    await db.commit()
    await db.refresh(a)
    return _app_out(a, me, me.id)


@router.post("/{app_id}/secret")
async def rotate_secret(
    app_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """چرخشِ کلید. نشست‌های صادرشده تا انقضایشان معتبر می‌مانند — برای ابطالِ
    فوری، برنامه باید معلق شود."""
    a = await _my_app(db, app_id, me)
    raw = secrets.token_urlsafe(32)
    a.secret_hash = _hash_secret(raw)
    await db.commit()
    return {"app_id": a.app_id, "app_secret": raw}


@router.post("/{app_id}/review", response_model=AppOut)
async def review_app(
    app_id: str,
    body: ReviewIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if me.role not in ("admin", "super_admin"):
        raise HTTPException(status_code=403, detail="دسترسی کافی ندارید")
    a = await _app_by_id(db, app_id)
    a.status = "approved" if body.approve else "rejected"
    a.review_note = (body.note or "").strip() or None
    a.reviewed_at = _now()
    await db.commit()
    await db.refresh(a)
    owners = await _owners(db, [a.owner_id])
    return _app_out(a, owners.get(a.owner_id), me.id)


# ── نصب و اجرا ───────────────────────────────────────────────────────────────
@router.post("/{app_id}/install", response_model=AppOut, status_code=201)
async def install_app(
    app_id: str,
    body: InstallIn | None = None,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """نصب = رضایتِ کاربر به فهرستِ دسترسی‌ها. نصبِ دوباره همان ردیف را
    به‌روز می‌کند (رضایتِ تازه)، نه ردیفِ دوم."""
    a = await _app_by_id(db, app_id)
    if a.status != "approved" and a.owner_id != me.id:
        raise HTTPException(status_code=403, detail="این برنامه هنوز تأیید نشده است")

    wanted = set(_split(a.scopes))
    asked = set(_clean_scopes(body.scopes)) if (body and body.scopes) else wanted
    extra = asked - wanted
    if extra:
        # کاربر نمی‌تواند دسترسی‌ای بدهد که برنامه اصلاً نخواسته است.
        raise HTTPException(status_code=400, detail="دسترسیِ خارج از فهرستِ برنامه")
    granted = ",".join(sorted(asked))

    inst = await _install_of(db, a.id, me.id)
    if inst is None:
        inst = MiniAppInstall(
            app_uid=a.id, user_id=me.id,
            open_id=_open_id(a.id, me.id), scopes=granted,
        )
        db.add(inst)
        try:
            await db.flush()
        except IntegrityError:
            # مسابقهٔ دو نصبِ هم‌زمان: ردیفِ موجود برنده است.
            await db.rollback()
            inst = await _install_of(db, a.id, me.id)
            if inst is None:
                raise HTTPException(status_code=409, detail="نصب ناموفق بود")
        else:
            a.install_count = int(a.install_count) + 1
    else:
        inst.scopes = granted
    await db.commit()
    await db.refresh(a)
    inst = await _install_of(db, a.id, me.id)
    owners = await _owners(db, [a.owner_id])
    return _app_out(a, owners.get(a.owner_id), me.id, inst)


@router.delete("/{app_id}/install", status_code=204)
async def uninstall_app(
    app_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    a = await _app_by_id(db, app_id)
    inst = await _install_of(db, a.id, me.id)
    if inst is not None:
        await db.delete(inst)
        a.install_count = max(0, int(a.install_count) - 1)
        await db.commit()


@router.post("/{app_id}/launch", response_model=LaunchOut)
async def launch_app(
    app_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کدِ یک‌بارمصرفِ ورود می‌سازد. کد در آدرس می‌رود چون webview باید آن را
    به backendِ برنامه برساند؛ عمرِ ۵ دقیقه‌ای و یک‌بارمصرف بودن، لو رفتنِ
    آدرس در لاگ‌ها را از یک نشستِ دائمی به یک پنجرهٔ کوتاه کاهش می‌دهد."""
    a = await _app_by_id(db, app_id)
    if a.status == "suspended":
        raise HTTPException(status_code=403, detail="این برنامه معلق است")
    if a.status != "approved" and a.owner_id != me.id:
        raise HTTPException(status_code=403, detail="این برنامه هنوز تأیید نشده است")

    inst = await _install_of(db, a.id, me.id)
    if inst is None:
        raise HTTPException(status_code=409, detail="ابتدا برنامه را نصب کنید")
    if set(_split(a.scopes)) - set(_split(inst.scopes)):
        raise HTTPException(
            status_code=409,
            detail="برنامه دسترسیِ تازه‌ای خواسته است؛ دوباره تأیید کنید",
        )

    code = secrets.token_urlsafe(24)
    inst.auth_code = code
    inst.auth_code_expires = _now() + timedelta(seconds=AUTH_CODE_TTL_SECONDS)
    inst.last_open_at = _now()
    inst.open_count = int(inst.open_count) + 1
    a.open_count = int(a.open_count) + 1
    await db.commit()

    sep = "&" if "?" in a.entry_url else "?"
    return LaunchOut(
        app_id=a.app_id,
        url=f"{a.entry_url}{sep}app_id={a.app_id}&code={code}",
        code=code, expires_in=AUTH_CODE_TTL_SECONDS,
    )


# ── پرداخت‌های منتظرِ تأییدِ کاربر ─────────────────────────────────────────────
@router.get("/payments/pending", response_model=List[PaymentOut])
async def pending_payments(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(MiniAppPayment).where(
            MiniAppPayment.user_id == me.id,
            MiniAppPayment.status == "pending",
            MiniAppPayment.expires_at > _now(),
        ).order_by(MiniAppPayment.created_at.desc()).limit(50)
    )).scalars().all()
    if not rows:
        return []
    apps = {a.id: a for a in (await db.execute(
        select(MiniApp).where(MiniApp.id.in_([p.app_uid for p in rows]))
    )).scalars().all()}
    return [_payment_out(p, apps[p.app_uid]) for p in rows if p.app_uid in apps]


@router.post("/payments/{ref}/confirm", response_model=PaymentOut)
async def confirm_payment(
    ref: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تنها جایی که پولِ کاربر بابتِ یک برنامه جابه‌جا می‌شود — و فقط با
    توکنِ خودِ کاربر. برنامه هیچ مسیری برای رسیدن به اینجا ندارد."""
    p = (await db.execute(
        select(MiniAppPayment).where(MiniAppPayment.ref == ref).with_for_update()
    )).scalar_one_or_none()
    if p is None or p.user_id != me.id:
        raise HTTPException(status_code=404, detail="درخواستِ پرداخت پیدا نشد")
    if _effective_status(p) != "pending":
        raise HTTPException(status_code=400, detail="این درخواست دیگر قابلِ پرداخت نیست")

    a = (await db.execute(
        select(MiniApp).where(MiniApp.id == p.app_uid)
    )).scalar_one()
    if a.status == "suspended":
        raise HTTPException(status_code=403, detail="این برنامه معلق است")

    amount = int(p.amount)
    commission = amount * COMMISSION_PCT // 100
    await move_money(
        db, me.id, a.owner_id, amount,
        out_desc=f"پرداخت در «{a.name}» — {p.subject}",
        in_desc=f"دریافت از «{a.name}» — {p.subject}",
        reference_id=p.ref,
        fee=commission,
        fee_desc=f"کارمزدِ دیلیکس ({COMMISSION_PCT}٪) — {p.ref}",
    )
    p.commission = commission
    p.status = "paid"
    p.paid_at = _now()
    await db.commit()
    await db.refresh(p)
    return _payment_out(p, a)


@router.post("/payments/{ref}/cancel", response_model=PaymentOut)
async def cancel_payment(
    ref: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = (await db.execute(
        select(MiniAppPayment).where(MiniAppPayment.ref == ref).with_for_update()
    )).scalar_one_or_none()
    if p is None or p.user_id != me.id:
        raise HTTPException(status_code=404, detail="درخواستِ پرداخت پیدا نشد")
    if _effective_status(p) != "pending":
        raise HTTPException(status_code=400, detail="این درخواست دیگر باز نیست")
    p.status = "cancelled"
    await db.commit()
    await db.refresh(p)
    a = (await db.execute(select(MiniApp).where(MiniApp.id == p.app_uid))).scalar_one()
    return _payment_out(p, a)


# ── جزئیاتِ یک برنامه (پس از روت‌های ثابت) ────────────────────────────────────
@router.get("/{app_id}", response_model=AppOut)
async def get_app(
    app_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    a = await _app_by_id(db, app_id)
    if a.status != "approved" and a.owner_id != me.id:
        raise HTTPException(status_code=404, detail="برنامه پیدا نشد")
    inst = await _install_of(db, a.id, me.id)
    owners = await _owners(db, [a.owner_id])
    return _app_out(a, owners.get(a.owner_id), me.id, inst)


# ── SDK: احرازِ هویتِ خودِ برنامه ──────────────────────────────────────────────
sdk_bearer = HTTPBearer(auto_error=True)


class SdkContext(BaseModel):
    app_uid: str
    open_id: str
    scopes: List[str]
    user_id: str

    model_config = {"arbitrary_types_allowed": True}


async def sdk_session(
    credentials: HTTPAuthorizationCredentials = Depends(sdk_bearer),
) -> SdkContext:
    """توکنِ نشستِ برنامه.

    `type` عمداً `miniapp` است و نه `access`: توکنِ نشستِ یک برنامه هرگز نباید
    روی اندپوینت‌های کاربر کار کند، و توکنِ کاربر هم نباید اینجا پذیرفته شود.
    هر دو سمت این ادعا را جداگانه بررسی می‌کنند.
    """
    try:
        payload = decode_token(credentials.credentials)
    except JWTError:
        raise HTTPException(status_code=401, detail="نشستِ نامعتبر یا منقضی")
    if payload.get("type") != "miniapp":
        raise HTTPException(status_code=401, detail="نشستِ نامعتبر")
    return SdkContext(
        app_uid=payload["app"], open_id=payload["open_id"],
        scopes=payload.get("scopes", []), user_id=payload["sub"],
    )


def _require_scope(ctx: SdkContext, scope: str) -> None:
    if scope not in ctx.scopes:
        raise HTTPException(
            status_code=403,
            detail=f"دسترسیِ «{SCOPES.get(scope, scope)}» به این برنامه داده نشده است",
        )


@router.post("/sdk/session", response_model=SessionOut)
async def sdk_exchange_code(
    body: SessionIn,
    db: AsyncSession = Depends(get_db),
):
    """تبادلِ کدِ یک‌بارمصرف با توکنِ نشست. تنها اندپوینتی که کلیدِ مخفی را
    می‌گیرد؛ باقیِ SDK با توکنِ کوتاه‌عمر کار می‌کند تا کلید در هر درخواست
    روی سیم نرود."""
    a = (await db.execute(
        select(MiniApp).where(MiniApp.app_id == body.app_id)
    )).scalar_one_or_none()
    # پیامِ یکسان برای «برنامه نیست» و «کلید غلط است» تا فهرستِ برنامه‌های
    # موجود از راهِ خطاها بیرون نریزد.
    if a is None or not hmac.compare_digest(a.secret_hash, _hash_secret(body.app_secret)):
        raise HTTPException(status_code=401, detail="شناسه یا کلیدِ برنامه نادرست است")
    if a.status == "suspended":
        raise HTTPException(status_code=403, detail="این برنامه معلق است")

    inst = (await db.execute(
        select(MiniAppInstall).where(
            MiniAppInstall.app_uid == a.id,
            MiniAppInstall.auth_code == body.code,
        ).with_for_update()
    )).scalar_one_or_none()
    if inst is None or not inst.auth_code_expires or inst.auth_code_expires <= _now():
        raise HTTPException(status_code=401, detail="کد نامعتبر یا منقضی است")

    inst.auth_code = None            # یک‌بارمصرف
    inst.auth_code_expires = None
    scopes = _split(inst.scopes)
    await db.commit()

    token = jwt.encode(
        {
            "sub": str(inst.user_id), "app": str(a.id),
            "open_id": inst.open_id, "scopes": scopes, "type": "miniapp",
            "exp": _now() + timedelta(seconds=SESSION_TTL_SECONDS),
        },
        settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM,
    )
    return SessionOut(session_token=token, open_id=inst.open_id,
                      scopes=scopes, expires_in=SESSION_TTL_SECONDS)


@router.get("/sdk/me", response_model=SdkMeOut)
async def sdk_me(
    ctx: SdkContext = Depends(sdk_session),
    db: AsyncSession = Depends(get_db),
):
    """هویتی که برنامه می‌بیند. بدونِ دسترسیِ `profile` فقط `open_id` — یعنی
    یک شناسهٔ پایدار برای ذخیرهٔ وضعیتِ بازی/سبدِ خرید، بی‌آنکه برنامه بداند
    کاربر کیست."""
    out = SdkMeOut(open_id=ctx.open_id, scopes=ctx.scopes)
    if "profile" in ctx.scopes or "location" in ctx.scopes:
        u = (await db.execute(
            select(User).where(User.id == _uuid.UUID(ctx.user_id))
        )).scalar_one_or_none()
        if u is not None:
            if "profile" in ctx.scopes:
                out.name = u.full_name or u.username or None
                out.avatar_url = u.avatar_url
            if "location" in ctx.scopes:
                out.country_code = u.country_code
                out.locale = u.locale
    return out


@router.post("/sdk/pay", response_model=PaymentOut, status_code=201)
async def sdk_request_payment(
    body: PayIn,
    ctx: SdkContext = Depends(sdk_session),
    db: AsyncSession = Depends(get_db),
):
    """برنامه فقط **درخواست** می‌سازد؛ وضعیتش `pending` است تا کاربر در خودِ
    دیلیکس تأیید کند. تکرارِ همان `out_trade_no` همان درخواست را برمی‌گرداند
    (۲۰۱ اما بدونِ ردیفِ دوم) — پس timeoutِ شبکه بدهیِ دوباره نمی‌سازد."""
    _require_scope(ctx, "payment")
    app_uid = _uuid.UUID(ctx.app_uid)
    a = (await db.execute(select(MiniApp).where(MiniApp.id == app_uid))).scalar_one()
    if a.status == "suspended":
        raise HTTPException(status_code=403, detail="این برنامه معلق است")

    trade = body.out_trade_no.strip()
    existing = (await db.execute(
        select(MiniAppPayment).where(
            MiniAppPayment.app_uid == app_uid,
            MiniAppPayment.out_trade_no == trade,
        )
    )).scalar_one_or_none()
    if existing is not None:
        return _payment_out(existing, a)

    p = MiniAppPayment(
        ref="MPP-" + _uuid.uuid4().hex[:10].upper(),
        app_uid=app_uid, user_id=_uuid.UUID(ctx.user_id),
        out_trade_no=trade, subject=body.subject.strip(), amount=body.amount,
        expires_at=_now() + timedelta(minutes=PAYMENT_TTL_MINUTES),
    )
    db.add(p)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        p = (await db.execute(
            select(MiniAppPayment).where(
                MiniAppPayment.app_uid == app_uid,
                MiniAppPayment.out_trade_no == trade,
            )
        )).scalar_one()
    await db.refresh(p)
    return _payment_out(p, a)


@router.get("/sdk/pay/{ref}", response_model=PaymentOut)
async def sdk_payment_status(
    ref: str,
    ctx: SdkContext = Depends(sdk_session),
    db: AsyncSession = Depends(get_db),
):
    """برنامه فقط پرداخت‌های **خودش** را می‌بیند — `app_uid` از توکن می‌آید،
    نه از ورودی."""
    p = (await db.execute(
        select(MiniAppPayment).where(
            MiniAppPayment.ref == ref,
            MiniAppPayment.app_uid == _uuid.UUID(ctx.app_uid),
        )
    )).scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="پرداخت پیدا نشد")
    a = (await db.execute(select(MiniApp).where(MiniApp.id == p.app_uid))).scalar_one()
    out = _payment_out(p, a)
    out.status = _effective_status(p)
    return out


async def expire_stale_payments(db: AsyncSession) -> int:
    """درخواست‌های سررسیدشده را می‌بندد. پولی جابه‌جا نشده، پس این فقط
    خانه‌تکانیِ فهرستِ کاربر است — درستیِ کار به `_effective_status` بند است."""
    rows = (await db.execute(
        select(MiniAppPayment).where(
            MiniAppPayment.status == "pending",
            MiniAppPayment.expires_at <= _now(),
        ).limit(500)
    )).scalars().all()
    for p in rows:
        p.status = "expired"
    if rows:
        await db.commit()
    return len(rows)
