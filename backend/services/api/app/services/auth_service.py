"""
Dilix — سرویس احراز هویت
Earth ID + JWT + Wallet اولیه
"""
import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import (
    create_access_token,
    hash_password,
    verify_password,
    create_refresh_token,
    decode_token,
    generate_earth_id,
)
from app.core.config import settings
from app.models.user import User
from app.models.wallet import Wallet

log = structlog.get_logger(__name__)


class AuthService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_or_create_user(self, phone: str) -> tuple[User, bool]:
        """
        پیدا کردن یا ساختن کاربر بر اساس شماره موبایل
        returns: (user, is_new_user)
        """
        result = await self.db.execute(
            select(User).where(User.phone == phone)
        )
        user = result.scalar_one_or_none()

        if user:
            return user, False

        # کاربر جدید — تخصیص Earth ID
        earth_id = generate_earth_id()

        # اطمینان از یکتا بودن Earth ID
        while True:
            existing = await self.db.execute(
                select(User).where(User.earth_id == earth_id)
            )
            if not existing.scalar_one_or_none():
                break
            earth_id = generate_earth_id()

        # تشخیص کشور از شماره
        country_code, locale = self._detect_locale(phone)

        user = User(
            phone=phone,
            earth_id=earth_id,
            status="active",
            kyc_level=1,  # تایید شماره = Level 1
            country_code=country_code,
            locale=locale,
            currency=self._currency_for_locale(locale),
        )
        self.db.add(user)
        await self.db.flush()

        # ساخت کیف پول اولیه
        wallet = Wallet(user_id=user.id, currency="IRR")
        self.db.add(wallet)
        await self.db.flush()

        log.info("user_created", earth_id=earth_id, phone_masked=phone[-4:], country=country_code)

        return user, True

    async def create_tokens(self, user: User) -> dict:
        """ساخت access + refresh token"""
        payload = {
            "sub": str(user.id),
            "earth_id": user.earth_id,
            "role": user.role,
            "phone": user.phone,
        }
        access = create_access_token(payload)
        refresh = create_refresh_token({"sub": str(user.id)})

        return {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            "earth_id": user.earth_id,
        }

    async def refresh_access_token(self, refresh_token: str) -> dict:
        """تجدید access token با refresh token"""
        from jose import JWTError
        try:
            payload = decode_token(refresh_token)
            if payload.get("type") != "refresh":
                raise ValueError("نوع توکن اشتباه است")
        except JWTError:
            raise ValueError("توکن نامعتبر یا منقضی شده")

        user_id = payload.get("sub")
        result = await self.db.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            raise ValueError("کاربر یافت نشد یا غیرفعال است")

        return await self.create_tokens(user)

    async def get_user_by_token(self, token: str) -> User:
        """دریافت کاربر از access token"""
        from jose import JWTError
        try:
            payload = decode_token(token)
            if payload.get("type") != "access":
                raise ValueError("نوع توکن اشتباه است")
        except JWTError:
            raise ValueError("توکن نامعتبر یا منقضی شده")

        user_id = payload.get("sub")
        result = await self.db.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()
        if not user:
            raise ValueError("کاربر یافت نشد")
        return user

    # --- helpers ---
    async def _unique_earth_id(self) -> str:
        earth_id = generate_earth_id()
        while True:
            existing = await self.db.execute(
                select(User).where(User.earth_id == earth_id)
            )
            if not existing.scalar_one_or_none():
                return earth_id
            earth_id = generate_earth_id()

    async def _create_wallet(self, user: User) -> None:
        wallet = Wallet(user_id=user.id, currency="IRR")
        self.db.add(wallet)
        await self.db.flush()

    # --- social / oauth ---
    async def login_or_register_oauth(self, claims) -> tuple[User, bool]:
        """ورود/ثبت‌نام بر اساسِ claimsِ تأییدشدهٔ provider. returns (user, is_new)."""
        provider = claims.provider
        subject = claims.subject
        email = (claims.email or "").strip().lower() or None

        user = None
        if email:
            res = await self.db.execute(select(User).where(User.email == email))
            user = res.scalar_one_or_none()

        if user:
            meta = dict(user.metadata_ or {})
            oauth = dict(meta.get("oauth") or {})
            oauth[provider] = subject
            meta["oauth"] = oauth
            user.metadata_ = meta
            if not user.full_name and claims.full_name:
                user.full_name = claims.full_name
            await self.db.flush()
            log.info("oauth_login", earth_id=user.earth_id, provider=provider)
            return user, False

        earth_id = await self._unique_earth_id()
        user = User(
            earth_id=earth_id,
            email=email,
            full_name=claims.full_name,
            status="active",
            kyc_level=1 if email else 0,
            locale="fa",
            currency="IRR",
            metadata_={"oauth": {provider: subject}},
        )
        self.db.add(user)
        await self.db.flush()
        await self._create_wallet(user)
        log.info("oauth_register", earth_id=earth_id, provider=provider)
        return user, True

    # --- email / password ---
    async def register_email(
        self, identifier: str, password: str, full_name: str
    ) -> tuple[User, bool]:
        """ثبت‌نام با ایمیل یا شماره + گذرواژه."""
        is_email = "@" in identifier
        col = User.email if is_email else User.phone
        res = await self.db.execute(select(User).where(col == identifier))
        if res.scalar_one_or_none():
            raise ValueError("این ایمیل/شماره قبلاً ثبت شده است")

        earth_id = await self._unique_earth_id()
        if is_email:
            country_code, locale = "INT", "en"
        else:
            country_code, locale = self._detect_locale(identifier)

        user = User(
            earth_id=earth_id,
            email=identifier if is_email else None,
            phone=None if is_email else identifier,
            full_name=full_name,
            password_hash=hash_password(password),
            status="active",
            kyc_level=0,
            country_code=country_code,
            locale=locale,
            currency=self._currency_for_locale(locale),
        )
        self.db.add(user)
        await self.db.flush()
        await self._create_wallet(user)
        log.info("email_register", earth_id=earth_id, is_email=is_email)
        return user, True

    async def login_email(self, identifier: str, password: str) -> User:
        """ورود با ایمیل یا شماره + گذرواژه."""
        is_email = "@" in identifier
        col = User.email if is_email else User.phone
        res = await self.db.execute(select(User).where(col == identifier))
        user = res.scalar_one_or_none()
        if not user or not user.password_hash:
            raise ValueError("ایمیل/شماره یا گذرواژه نادرست است")
        if not verify_password(password, user.password_hash):
            raise ValueError("ایمیل/شماره یا گذرواژه نادرست است")
        if not user.is_active:
            raise ValueError("این حساب غیرفعال است")
        return user

    @staticmethod
    def _detect_locale(phone: str) -> tuple[str, str]:
        """تشخیص کشور و زبان از کد کشور"""
        prefix_map = {
            "+98": ("IRN", "fa"),
            "+90": ("TUR", "tr"),
            "+7":  ("RUS", "ru"),
            "+971": ("ARE", "ar"),
            "+964": ("IRQ", "ar"),
            "+966": ("SAU", "ar"),
            "+1":  ("USA", "en"),
            "+44": ("GBR", "en"),
        }
        for prefix, (country, locale) in prefix_map.items():
            if phone.startswith(prefix):
                return country, locale
        return "INT", "en"

    @staticmethod
    def _currency_for_locale(locale: str) -> str:
        """ارزِ نمایشِ پیش‌فرض بر اساسِ زبانِ تشخیص‌داده‌شده (ISO 4217)."""
        return {
            "fa": "IRR", "en": "USD", "ar": "AED", "tr": "TRY", "ru": "RUB",
            "fr": "EUR", "de": "EUR", "es": "EUR", "zh": "CNY", "hi": "INR",
        }.get(locale, "USD")
