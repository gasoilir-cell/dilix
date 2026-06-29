"""تنظیماتِ dilix-ai-service. همه‌چیز از محیط خوانده می‌شود (Zero Trust)."""
from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="DILIX_AI_", extra="ignore")

    service_name: str = "ai"
    environment: str = Field(default="development")
    region: str = Field(default="IR")

    # ── LLM provider (OpenAI-compatible Chat Completions) ──
    # اگر api_key خالی باشد، سرویس به پاسخِ rule-based قطعی برمی‌گردد (بدونِ تماسِ خارجی).
    llm_base_url: str = Field(default="https://api.openai.com/v1")
    llm_api_key: str = Field(default="")
    llm_model: str = Field(default="gpt-4o-mini")
    llm_temperature: float = Field(default=0.3)
    llm_timeout_seconds: float = Field(default=30.0)
    llm_max_tokens: int = Field(default=1024)

    # ── MCP Tool Layer → فراخوانیِ برگشتی به dilix-core ──
    # برای اجرایِ ابزارهایِ دامنه (freight.search، insurance.quote، ...).
    core_base_url: str = Field(default="", description="http://dilix-core:8000 در production")
    core_service_token: str = Field(default="", description="توکنِ سرویس‌به‌سرویس برای MCP")
    mcp_timeout_seconds: float = Field(default=15.0)

    @property
    def llm_enabled(self) -> bool:
        return bool(self.llm_api_key)

    @property
    def mcp_enabled(self) -> bool:
        return bool(self.core_base_url)

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
