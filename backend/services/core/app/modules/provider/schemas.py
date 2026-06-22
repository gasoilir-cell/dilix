"""Schemaهای Provider (سند ۵: /v1/providers/...)."""
from __future__ import annotations

import uuid
from typing import Literal

from pydantic import BaseModel, Field

ProviderType = Literal["insurer", "carrier", "psp", "telecom", "third_party"]


class ProviderRegisterRequest(BaseModel):
    legal_name: str = Field(min_length=2, max_length=255)
    provider_type: ProviderType
    country: str = Field(default="IR", max_length=8)
    license_no: str | None = Field(default=None, max_length=128)


class ProviderOut(BaseModel):
    id: uuid.UUID
    legal_name: str
    provider_type: str
    country: str
    kyb_status: str


class ProviderApiCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    spec_url: str | None = Field(default=None, max_length=512)
    webhook_url: str | None = Field(default=None, max_length=512)


class ProviderApiOut(BaseModel):
    id: uuid.UUID
    name: str
    env: str
    status: str
