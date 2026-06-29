"""تنظیمات سرویس Core. مقادیر از محیط خوانده می‌شوند (Zero Trust: هیچ secret در کد)."""
from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="DILIX_", extra="ignore")

    # هویت سرویس و ریجن (ADR-04: Hybrid Multi-Region)
    service_name: str = "core"
    region: str = Field(default="IR", description="کد ریجن: IR, RU, OM, TR ...")
    environment: str = Field(default="development")

    # پایگاه‌داده
    database_url: str = Field(
        default="postgresql+asyncpg://dilix:dilix@localhost:5432/dilix_core"
    )
    redis_url: str = Field(default="redis://localhost:6379/0")

    # امنیت (سند ۶)
    jwt_secret: str = Field(default="dev-only-change-me")
    jwt_algorithm: str = "HS256"
    access_token_ttl_seconds: int = 900   # ≤ 15m مطابق سند امنیت
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 14

    # Event Backbone
    event_broker_url: str = Field(default="nats://localhost:4222")

    # ارائه‌دهنده‌ی پرداختِ بانک سامان (اختیاری)
    saman_base_url: str = Field(default="")
    saman_terminal_id: str = Field(default="")
    saman_secret: str = Field(default="")

    # AI Service — dilix-ai-service (LangGraph)
    ai_service_url: str = Field(default="", description="http://dilix-ai:8001 در production")

    # Observability — OpenTelemetry
    otel_enabled: bool = Field(default=False)
    otel_exporter_otlp_endpoint: str = Field(default="http://localhost:4317")
    otel_service_name: str = Field(default="dilix-core")

    # i18n — زبان پیش‌فرض پاسخ‌های API
    default_locale: str = Field(default="fa", description="fa | en | ru | ar | tr")

    # آدرس عمومی اپ — برای ساختِ لینکِ دعوت (Growth)
    public_app_url: str = Field(default="https://dilix.app")

    # MinIO (ذخیره‌سازی رسانه)
    minio_endpoint: str = Field(default="localhost:9000")
    minio_access_key: str = Field(default="")
    minio_secret_key: str = Field(default="")
    minio_bucket: str = Field(default="dilix-media")

    # Elasticsearch
    elasticsearch_url: str = Field(default="http://localhost:9200")

    # ─────────────────── ورودِ فدراسیون (OAuth2/OIDC) ───────────────────
    # هر کدام Client ID مجاز است؛ چند ID با کاما جدا می‌شود (وب/iOS/اندروید).
    google_client_ids: str = Field(default="", description="Client IDهای مجازِ Google (با کاما)")
    microsoft_client_ids: str = Field(default="", description="Client IDهای مجازِ Microsoft (با کاما)")
    microsoft_tenant: str = Field(default="common", description="common | organizations | <tenant-id>")
    apple_client_ids: str = Field(default="", description="Service/Bundle IDهای مجازِ Apple (با کاما)")
    facebook_app_id: str = Field(default="", description="App ID فیسبوک برای اعتبارسنجیِ توکن")
    facebook_app_secret: str = Field(default="", description="App Secret فیسبوک")

    # ─────────────────── کدِ یک‌بارمصرف (OTP) ───────────────────
    otp_length: int = Field(default=6, ge=4, le=8)
    otp_ttl_seconds: int = Field(default=300, description="پنجره‌ی اعتبارِ کد (پیش‌فرض ۵ دقیقه)")
    otp_max_attempts: int = Field(default=5, description="بیشینه‌ی تلاشِ تأیید برای هر چالش")
    # فرستنده‌ی پیامک
    sms_base_url: str = Field(default="", description="آدرسِ درگاهِ پیامک")
    sms_api_key: str = Field(default="")
    sms_sender: str = Field(default="", description="شماره/نامِ فرستنده")
    # فرستنده‌ی فیسبوک مسنجر (Send API)
    facebook_page_token: str = Field(default="", description="Page Access Token برای ارسالِ پیام")

    @property
    def saman_enabled(self) -> bool:
        return bool(self.saman_base_url and self.saman_secret)

    @staticmethod
    def _csv(value: str) -> set[str]:
        return {item.strip() for item in value.split(",") if item.strip()}

    @property
    def google_client_id_set(self) -> set[str]:
        return self._csv(self.google_client_ids)

    @property
    def microsoft_client_id_set(self) -> set[str]:
        return self._csv(self.microsoft_client_ids)

    @property
    def apple_client_id_set(self) -> set[str]:
        return self._csv(self.apple_client_ids)

    @property
    def sms_enabled(self) -> bool:
        return bool(self.sms_base_url and self.sms_api_key)

    @property
    def facebook_otp_enabled(self) -> bool:
        return bool(self.facebook_page_token)

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
