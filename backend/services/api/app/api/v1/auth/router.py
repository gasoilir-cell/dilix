"""
Dilix — Auth Router
POST /api/v1/auth/otp/send
POST /api/v1/auth/otp/verify
POST /api/v1/auth/refresh
GET  /api/v1/auth/me
"""
from fastapi import APIRouter, Depends, HTTPException, Request, status, UploadFile, File, Form, Query
import os, uuid as _uuid, shutil, re as _re
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, Column, String, Integer, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID as _PGUUID

from app.core.database import get_db, Base
from app.core.redis import get_redis
from app.core.ratelimit import OTP_DESTINATION_RULE, hit as ratelimit_hit
from app.schemas.auth import (
    EmailLoginRequest,
    EmailRegisterRequest,
    OAuthLoginRequest,
    RefreshTokenRequest,
    SendOTPRequest,
    TokenResponse,
    UpdateProfileRequest,
    UserResponse,
    VerifyOTPRequest,
)
from app.services.auth_service import AuthService
from app.services.geo_service import record_login_geo
from app.services.otp_service import OTPService
from app.services import oauth_service
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/otp/send", summary="ارسال کد تایید OTP")
async def send_otp(
    body: SendOTPRequest,
    db: AsyncSession = Depends(get_db),
    redis=Depends(get_redis),
):
    """
    ارسال OTP به شماره موبایل.
    در محیط development کد در console نمایش داده می‌شود.
    """
    # سقفِ ارسال به یک شماره، مستقل از IP: cooldownِ ۳۰ ثانیه‌ای به‌تنهایی یعنی
    # ۱۲۰ پیامک در ساعت روی شماره‌ی قربانی، و هر پیامک هزینه‌ی واقعی دارد.
    await ratelimit_hit(f"otp:send:{body.purpose}", body.phone, OTP_DESTINATION_RULE)

    otp_service = OTPService(redis)
    result = await otp_service.send_otp(body.phone, body.purpose)

    if not result["sent"]:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=result,
        )
    return result


@router.post(
    "/otp/verify",
    response_model=TokenResponse,
    summary="تایید OTP و ورود / ثبت‌نام",
)
async def verify_otp(
    body: VerifyOTPRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis=Depends(get_redis),
):
    """
    تایید کد OTP.
    اگر کاربر جدید باشد ثبت‌نام می‌شود، اگر قبلی باشد وارد می‌شود.
    Earth ID یکتا تخصیص داده می‌شود.
    """
    otp_service = OTPService(redis)
    verify_result = await otp_service.verify_otp(body.phone, body.otp)

    if not verify_result["valid"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=verify_result,
        )

    auth_service = AuthService(db)
    user, is_new = await auth_service.get_or_create_user(body.phone)

    # آپدیت IP آخرین ورود
    await record_login_geo(user, request)

    tokens = await auth_service.create_tokens(user)
    tokens["is_new_user"] = is_new

    return tokens


@router.post(
    "/oauth/{provider}",
    response_model=TokenResponse,
    summary="ورود/ثبت‌نام با شبکهٔ اجتماعی (Google/Microsoft/Apple/Facebook)",
)
async def oauth_login(
    provider: str,
    body: OAuthLoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    توکنِ provider در سمتِ سرور تأیید می‌شود (امضا/مخاطب).
    اگر ایمیلِ کاربر قبلاً موجود باشد وارد می‌شود، وگرنه حساب جدید ساخته می‌شود.
    """
    try:
        claims = await oauth_service.verify(provider, body.credential)
    except oauth_service.OAuthError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="ارتباط با سرویسِ ورودِ اجتماعی ناموفق بود",
        )

    auth_service = AuthService(db)
    user, is_new = await auth_service.login_or_register_oauth(claims)
    await record_login_geo(user, request)

    tokens = await auth_service.create_tokens(user)
    tokens["is_new_user"] = is_new
    return tokens


@router.post(
    "/register",
    response_model=TokenResponse,
    summary="ثبت‌نام با ایمیل/شماره + گذرواژه",
)
async def register_email(
    body: EmailRegisterRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    auth_service = AuthService(db)
    try:
        user, is_new = await auth_service.register_email(
            body.identifier, body.password, body.full_name
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))

    await record_login_geo(user, request)
    tokens = await auth_service.create_tokens(user)
    tokens["is_new_user"] = is_new
    return tokens


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="ورود با ایمیل/شماره + گذرواژه",
)
async def login_email(
    body: EmailLoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    auth_service = AuthService(db)
    try:
        user = await auth_service.login_email(body.identifier, body.password)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))

    await record_login_geo(user, request)
    tokens = await auth_service.create_tokens(user)
    tokens["is_new_user"] = False
    return tokens


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="تجدید access token",
)
async def refresh_token(
    body: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    try:
        auth_service = AuthService(db)
        return await auth_service.refresh_access_token(body.refresh_token)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )


@router.get(
    "/me",
    response_model=UserResponse,
    summary="اطلاعات کاربر فعلی",
)
async def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": str(current_user.id),
        "earth_id": current_user.earth_id,
        "phone": current_user.phone,
        "email": current_user.email,
        "full_name": current_user.full_name,
        "username": current_user.username,
        "avatar_url": current_user.avatar_url,
        "bio": current_user.bio,
        "role": current_user.role,
        "tier": current_user.tier,
        "status": current_user.status,
        "kyc_level": current_user.kyc_level,
        "kyc_status": current_user.kyc_status or "pending",
        "national_id_set": bool(current_user.national_id),
        "locale": current_user.locale,
        "country_code": current_user.country_code,
        "is_driver": current_user.is_driver,
        "trust_score": current_user.trust_score,
        "avg_rating": current_user.avg_rating,
        "total_trips": current_user.total_trips,
        "privacy_on_map": current_user.privacy_on_map,
        "created_at": current_user.created_at.isoformat(),
    }


@router.patch(
    "/me",
    response_model=UserResponse,
    summary="آپدیت پروفایل",
)
async def update_profile(
    body: UpdateProfileRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from sqlalchemy import select
    # بررسی یکتایی username
    if body.username and body.username != current_user.username:
        existing = await db.execute(
            select(User).where(User.username == body.username)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="این نام کاربری قبلاً استفاده شده است",
            )

    for field, value in body.model_dump(exclude_none=True).items():
        setattr(current_user, field, value)

    await db.flush()

    return {
        "id": str(current_user.id),
        "earth_id": current_user.earth_id,
        "phone": current_user.phone,
        "email": current_user.email,
        "full_name": current_user.full_name,
        "username": current_user.username,
        "avatar_url": current_user.avatar_url,
        "bio": current_user.bio,
        "role": current_user.role,
        "tier": current_user.tier,
        "status": current_user.status,
        "kyc_level": current_user.kyc_level,
        "kyc_status": current_user.kyc_status or "pending",
        "national_id_set": bool(current_user.national_id),
        "locale": current_user.locale,
        "country_code": current_user.country_code,
        "is_driver": current_user.is_driver,
        "trust_score": current_user.trust_score,
        "avg_rating": current_user.avg_rating,
        "total_trips": current_user.total_trips,
        "privacy_on_map": current_user.privacy_on_map,
        "created_at": current_user.created_at.isoformat(),
    }


AVATAR_DIR = "/var/www/dilix-api/uploads/avatars"
AVATAR_BASE_URL = "/uploads/avatars"
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_SIZE = 5 * 1024 * 1024  # 5 MB


@router.post(
    "/me/avatar",
    summary="آپلود عکس پروفایل",
)
async def upload_avatar(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="فرمت فایل پشتیبانی نمی‌شود. JPG، PNG، WEBP یا GIF ارسال کن",
        )

    # خواندن محتوا و بررسی حجم
    data = await file.read()
    if len(data) > MAX_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="حجم عکس نباید بیشتر از ۵ مگابایت باشد",
        )

    # ذخیره با نام یکتا
    ext = os.path.splitext(file.filename or "avatar.jpg")[1].lower() or ".jpg"
    filename = f"{current_user.earth_id}_{_uuid.uuid4().hex[:8]}{ext}"
    os.makedirs(AVATAR_DIR, exist_ok=True)
    filepath = os.path.join(AVATAR_DIR, filename)

    with open(filepath, "wb") as f:
        f.write(data)

    # آپدیت URL در دیتابیس
    avatar_url = f"{AVATAR_BASE_URL}/{filename}"
    current_user.avatar_url = avatar_url
    await db.flush()

    return {"avatar_url": avatar_url, "message": "عکس پروفایل با موفقیت آپلود شد"}


# ═══════════════════════════════════════════════════════════════
#  KYC — احرازِ هویت (سطح ۲: مدارکِ هویتی)
# ═══════════════════════════════════════════════════════════════
KYC_DIR = "/var/www/dilix-api/uploads/kyc"
KYC_BASE_URL = "/uploads/kyc"
KYC_IMG_TYPES = {"image/jpeg", "image/png", "image/webp"}
KYC_MAX_SIZE = 8 * 1024 * 1024  # 8 MB


def _valid_iran_national_id(code: str) -> bool:
    """اعتبارسنجیِ کدِ ملیِ ۱۰رقمیِ ایران (رقمِ کنترلی)."""
    if not _re.fullmatch(r"\d{10}", code or ""):
        return False
    if code == code[0] * 10:  # ارقامِ یکسان (۰۰۰۰۰۰۰۰۰۰ و …) نامعتبر
        return False
    s = sum(int(code[i]) * (10 - i) for i in range(9))
    r = s % 11
    check = int(code[9])
    return check == r if r < 2 else check == 11 - r


class KycRequest(Base):
    """درخواستِ احرازِ هویت — تاریخچه + صفِ بررسیِ ادمین."""
    __tablename__ = "kyc_requests"
    id            = Column(_PGUUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id       = Column(_PGUUID(as_uuid=True), index=True, nullable=False)
    level         = Column(Integer, default=2, nullable=False)        # سطحِ درخواستی
    full_name     = Column(String(200), nullable=True)
    national_id   = Column(String(20), nullable=True)
    date_of_birth = Column(String(20), nullable=True)                 # ISO (YYYY-MM-DD)
    doc_front_url = Column(Text, nullable=True)                       # کارتِ ملی/شناسنامه
    doc_selfie_url= Column(Text, nullable=True)                       # سلفی با مدرک
    status        = Column(String(12), default="pending", nullable=False, index=True)  # pending/approved/rejected
    review_note   = Column(Text, nullable=True)
    reviewed_by   = Column(_PGUUID(as_uuid=True), nullable=True)
    created_at    = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    reviewed_at   = Column(DateTime(timezone=True), nullable=True)


async def _save_kyc_file(file: UploadFile, earth_id: str, tag: str) -> str:
    if file.content_type not in KYC_IMG_TYPES:
        raise HTTPException(status_code=400, detail="فرمتِ مدرک باید JPG، PNG یا WEBP باشد")
    data = await file.read()
    if len(data) > KYC_MAX_SIZE:
        raise HTTPException(status_code=413, detail="حجمِ هر مدرک نباید بیشتر از ۸ مگابایت باشد")
    if not data:
        raise HTTPException(status_code=400, detail="فایلِ مدرک خالی است")
    ext = os.path.splitext(file.filename or f"{tag}.jpg")[1].lower() or ".jpg"
    fname = f"{earth_id}_{tag}_{_uuid.uuid4().hex[:8]}{ext}"
    os.makedirs(KYC_DIR, exist_ok=True)
    with open(os.path.join(KYC_DIR, fname), "wb") as f:
        f.write(data)
    return f"{KYC_BASE_URL}/{fname}"


def _kyc_out(req: "KycRequest | None"):
    if req is None:
        return {"status": "none"}
    return {
        "id": str(req.id),
        "level": req.level,
        "status": req.status,
        "review_note": req.review_note,
        "created_at": req.created_at.isoformat() if req.created_at else None,
    }


@router.get("/me/kyc", summary="وضعیتِ درخواستِ احرازِ هویتِ من")
async def my_kyc(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    r = await db.execute(
        select(KycRequest).where(KycRequest.user_id == current_user.id)
        .order_by(KycRequest.created_at.desc()).limit(1)
    )
    return _kyc_out(r.scalar_one_or_none())


@router.post("/me/kyc", summary="ثبتِ درخواستِ احرازِ هویت (سطح ۲)")
async def submit_kyc(
    national_id: str = Form(...),
    full_name: str = Form(...),
    date_of_birth: str = Form(...),
    front: UploadFile = File(...),
    selfie: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ثبتِ مدارکِ هویتی برای ارتقا به سطح ۲.
    کدِ ملی اعتبارسنجی می‌شود؛ درخواست در وضعیتِ `pending` برای بررسیِ ادمین ثبت می‌شود."""
    if current_user.kyc_level >= 2:
        raise HTTPException(status_code=400, detail="هویتِ شما پیش‌تر تأیید شده است")
    # جلوگیری از درخواستِ تکراریِ در انتظار
    dup = await db.execute(
        select(KycRequest).where(
            KycRequest.user_id == current_user.id,
            KycRequest.status == "pending",
        )
    )
    if dup.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="یک درخواستِ در حالِ بررسی دارید")

    code = (national_id or "").strip()
    if not _valid_iran_national_id(code):
        raise HTTPException(status_code=400, detail="کدِ ملی معتبر نیست")
    name = (full_name or "").strip()
    if len(name) < 3:
        raise HTTPException(status_code=400, detail="نامِ کامل را وارد کنید")
    dob = (date_of_birth or "").strip()
    if not _re.fullmatch(r"\d{4}-\d{2}-\d{2}", dob):
        raise HTTPException(status_code=400, detail="تاریخِ تولد را به شکلِ درست وارد کنید")

    front_url = await _save_kyc_file(front, current_user.earth_id, "front")
    selfie_url = await _save_kyc_file(selfie, current_user.earth_id, "selfie")

    req = KycRequest(
        user_id=current_user.id, level=2, full_name=name, national_id=code,
        date_of_birth=dob, doc_front_url=front_url, doc_selfie_url=selfie_url,
        status="pending",
    )
    db.add(req)
    current_user.full_name = current_user.full_name or name
    current_user.national_id = code
    current_user.kyc_status = "pending"
    await db.flush()
    return {"status": "pending", "message": "مدارکِ شما ثبت شد و در حالِ بررسی است"}


def _require_admin(current_user: User):
    if current_user.role not in ("admin", "super_admin"):
        raise HTTPException(status_code=403, detail="دسترسی کافی ندارید")


@router.get("/admin/kyc", summary="[ادمین] صفِ درخواست‌های احرازِ هویت")
async def admin_list_kyc(
    status_filter: str = Query("pending", alias="status"),
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)
    q = select(KycRequest).order_by(KycRequest.created_at.desc()).limit(limit)
    if status_filter and status_filter != "all":
        q = q.where(KycRequest.status == status_filter)
    rows = (await db.execute(q)).scalars().all()
    return [
        {
            "id": str(x.id), "user_id": str(x.user_id), "level": x.level,
            "full_name": x.full_name, "national_id": x.national_id,
            "date_of_birth": x.date_of_birth, "doc_front_url": x.doc_front_url,
            "doc_selfie_url": x.doc_selfie_url, "status": x.status,
            "created_at": x.created_at.isoformat() if x.created_at else None,
        }
        for x in rows
    ]


@router.post("/admin/kyc/{req_id}/review", summary="[ادمین] بررسیِ درخواستِ احرازِ هویت")
async def admin_review_kyc(
    req_id: str,
    approve: bool = Form(...),
    note: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)
    req = await db.get(KycRequest, _uuid.UUID(req_id))
    if not req:
        raise HTTPException(status_code=404, detail="درخواست پیدا نشد")
    if req.status != "pending":
        raise HTTPException(status_code=400, detail="این درخواست قبلاً بررسی شده است")
    target = await db.get(User, req.user_id)
    req.reviewed_by = current_user.id
    req.reviewed_at = datetime.now(timezone.utc)
    req.review_note = (note or "").strip() or None
    if approve:
        req.status = "approved"
        if target:
            target.kyc_level = max(int(target.kyc_level or 0), int(req.level))
            target.kyc_status = "approved"
    else:
        req.status = "rejected"
        if target:
            target.kyc_status = "rejected"
    await db.flush()
    return {"status": req.status}
