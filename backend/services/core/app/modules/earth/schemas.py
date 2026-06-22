from __future__ import annotations
import uuid
from pydantic import BaseModel, Field


class LocationUpdate(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    geo_precision: str = Field(
        default="region", pattern="^(exact|district|city|region)$"
    )
    is_visible: bool = False
    country_code: str | None = Field(default=None, max_length=4)


class PoiCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=64)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    country_code: str = Field(min_length=2, max_length=4)


class LocationOut(BaseModel):
    earth_id: uuid.UUID
    lat: float
    lon: float
    geo_precision: str
    is_visible: bool
    model_config = {"from_attributes": True}


class PoiOut(BaseModel):
    id: uuid.UUID
    name: str
    category: str
    lat: float
    lon: float
    country_code: str
    model_config = {"from_attributes": True}
