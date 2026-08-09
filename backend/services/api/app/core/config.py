"""
Dilix — تنظیمات مرکزی برنامه
"""
from functools import lru_cache
from typing import Literal
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ─── App ─────────────────────────────────────────────────
    ENV: Literal["development", "staging", "production"] = "development"
    APP_NAME: str = "Dilix"
    APP_VERSION: str = "1.0.0"
    APP_URL: str = "http://localhost:3000"
    DEBUG: bool = True

    # ─── Database ─────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://dilix:dilix_dev_pass@localhost:5432/dilix"
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20

    # ─── Redis ────────────────────────────────────────────────
    REDIS_URL: str = "redis://:dilix_redis_pass@localhost:6379/0"

    # ─── JWT ──────────────────────────────────────────────────
    JWT_SECRET: str = "change_this_in_production_minimum_32_chars"

    # ── WebRTC TURN/STUN (coturn) ─────────────────────────
    TURN_HOST: str = ""              # آی‌پی/هاستِ coturn برای turn:/stun:
    TURN_TLS_HOST: str = ""          # هاستِ منطبق با گواهیِ TLS برای turns:
    TURN_SECRET: str = ""            # static-auth-secret مشترک با coturn
    TURN_REALM: str = "dilix.ir"
    TURN_TTL: int = 86400            # عمرِ کردنشالِ HMAC (ثانیه)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # ─── OTP ──────────────────────────────────────────────────
    OTP_EXPIRE_SECONDS: int = 120
    OTP_LENGTH: int = 6
    OTP_MAX_ATTEMPTS: int = 5

    # ─── CORS ─────────────────────────────────────────────────
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:3001"

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",")]

    # ─── SMS ──────────────────────────────────────────────────
    SMS_PROVIDER: str = "console"  # console | magfa | twilio
    MAGFA_USERNAME: str = ""
    MAGFA_PASSWORD: str = ""
    MAGFA_SENDER: str = "Dilix"
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_FROM_NUMBER: str = ""

    # ─── Social / OAuth (ورودِ اجتماعی) ───────────────────────
    GOOGLE_CLIENT_IDS: str = ""      # چند مقدار با , جدا (وب + موبایل)
    MICROSOFT_CLIENT_IDS: str = ""
    APPLE_CLIENT_IDS: str = ""       # Service ID(های) Apple
    FACEBOOK_APP_ID: str = ""
    FACEBOOK_APP_SECRET: str = ""

    # ─── Push ─────────────────────────────────────────────────
    PUSHE_APP_ID: str = ""
    PUSHE_TOKEN: str = ""
    FCM_SERVER_KEY: str = ""

    # ─── Payment ──────────────────────────────────────────────
    ZARINPAL_MERCHANT_ID: str = ""
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""
    TWILIO_PHONE_NUMBER: str = ""

    # ─── AI ───────────────────────────────────────────────────
    OPENAI_API_KEY: str = ""
    ANTHROPIC_API_KEY: str = ""
    LOCAL_LLM_URL: str = "http://localhost:11434"

    # ─── ترجمه ────────────────────────────────────────────────
    # مسیرِ سازگار با OpenAI. `TRANSLATE_BASE_URL` قابل تنظیم است چون از سرورِ
    # ایران api.anthropic.com پاسخِ 403 می‌دهد؛ هر درگاهِ سازگار (OpenRouter،
    # AvalAI، Metis، Ollama محلی) با همین یک فیلد جایگزین می‌شود.
    TRANSLATE_BASE_URL: str = "https://api.openai.com/v1"
    TRANSLATE_API_KEY: str = ""      # خالی → از OPENAI_API_KEY خوانده می‌شود
    TRANSLATE_MODEL: str = "gpt-4o-mini"
    TRANSLATE_MODEL_ANTHROPIC: str = "claude-haiku-4-5-20251001"

    @property
    def is_production(self) -> bool:
        return self.ENV == "production"

    @property
    def is_development(self) -> bool:
        return self.ENV == "development"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
