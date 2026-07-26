"""
Dilix — Earth Map API
کاربران با موقعیت مکانی روی کره زمین
"""
from __future__ import annotations

import hashlib
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.geo_service import reverse_geocode

router = APIRouter(prefix="/earth", tags=["Earth"])

# نقاط مرکزی کشورها (ISO 3166-1 alpha-3 → lat, lng) — فقط fallback
_COUNTRY_COORDS: dict[str, tuple[float, float]] = {
    "IRN": (32.4279, 53.6880),
    "ARE": (23.4241, 53.8478),
    "TUR": (38.9637, 35.2433),
    "DEU": (51.1657, 10.4515),
    "GBR": (55.3781, -3.4360),
    "JPN": (36.2048, 138.2529),
    "USA": (37.0902, -95.7129),
    "CHN": (35.8617, 104.1954),
    "RUS": (61.5240, 105.3188),
    "IND": (20.5937, 78.9629),
    "PAK": (30.3753, 69.3451),
    "AFG": (33.9391, 67.7100),
    "IRQ": (33.2232, 43.6793),
    "SAU": (23.8859, 45.0792),
    "QAT": (25.3548, 51.1839),
    "KWT": (29.3117, 47.4818),
    "BHR": (26.0275, 50.5500),
    "OMN": (21.4735, 55.9754),
    "AZE": (40.1431, 47.5769),
    "KAZ": (48.0196, 66.9237),
    "UZB": (41.3775, 64.5853),
    "TKM": (38.9697, 59.5563),
    "ARM": (40.0691, 45.0382),
    "GEO": (42.3154, 43.3569),
    "FRA": (46.2276, 2.2137),
    "ITA": (41.8719, 12.5674),
    "ESP": (40.4637, -3.7492),
    "NLD": (52.1326, 5.2913),
    "CHE": (46.8182, 8.2275),
    "SWE": (60.1282, 18.6435),
    "NOR": (60.4720, 8.4689),
    "AUS": (-25.2744, 133.7751),
    "CAN": (56.1304, -106.3468),
    "BRA": (-14.2350, -51.9253),
    "ZAF": (-30.5595, 22.9375),
    "EGY": (26.8206, 30.8025),
    "NGA": (9.0820, 8.6753),
    "KOR": (35.9078, 127.7669),
    "SGP": (1.3521, 103.8198),
    "MYS": (4.2105, 101.9758),
    "THA": (15.8700, 100.9925),
    "IDN": (-0.7893, 113.9213),
    "PHL": (12.8797, 121.7740),
    "VNM": (14.0583, 108.2772),
}


def _seed_jitter(seed: str, lat: float, lng: float, scale: float) -> tuple[float, float]:
    """
    پراکندگی قطعی (بر پایه‌ی earth_id) — بین fetchها ثابت می‌ماند و
    کاربرانِ هم‌مکان را کمی از هم جدا می‌کند (بدون پرش تصادفی).
    """
    h = hashlib.md5(seed.encode()).digest()
    r1 = (h[0] | (h[1] << 8)) / 65535.0  # 0..1
    r2 = (h[2] | (h[3] << 8)) / 65535.0
    return lat + (r1 * 2 - 1) * scale, lng + (r2 * 2 - 1) * scale


def _fuzz_area(seed: str, lat: float, lng: float) -> tuple[float, float]:
    """
    موقعیتِ GPS دقیق را برای نمایش به دیگران به «محدوده» تبدیل می‌کند:
    کاهش دقت (round به ۲ رقم ≈ ۱ کیلومتر) + پراکندگیِ قطعی.
    موقعیتِ دقیق فقط در DB (metadata.geo_gps) برای ادمین باقی می‌ماند.
    """
    return _seed_jitter(seed, round(lat, 2), round(lng, 2), 0.02)


class LocationUpdate(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    accuracy: float | None = Field(None, ge=0)


@router.post("/location", summary="ثبت موقعیت دقیق کاربر از GPS")
async def update_location(
    body: LocationUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    موقعیتِ دقیقِ GPS کاربر را ذخیره می‌کند (برای ادمین دقیق، برای دیگران
    روی نقشه به‌صورت محدوده fuzz می‌شود). نام شهر با reverse geocoding پر می‌شود.
    """
    try:
        geo = await reverse_geocode(body.lat, body.lng)
    except Exception:
        geo = None
    geo = geo or {}

    meta = dict(current_user.metadata_ or {})
    meta["geo_gps"] = {
        "lat": body.lat,
        "lng": body.lng,
        "accuracy": body.accuracy,
        "city": geo.get("city"),
        "region": geo.get("region"),
        "cc": geo.get("cc"),
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    current_user.metadata_ = meta
    if geo.get("cc") and not current_user.country_code:
        current_user.country_code = geo["cc"]
    # ثبت موقعیت = فعالیت زنده؛ کاربر را آنلاین کن
    current_user.last_login_at = datetime.now(timezone.utc)
    await db.flush()

    return {"ok": True, "city": geo.get("city")}


@router.get("/users", summary="کاربران روی کره زمین")
async def get_earth_users(
    type: str | None = Query(None, description="driver|person|business"),
    country: str | None = Query(None, description="ISO 3166-1 alpha-3"),
    limit: int = Query(200, le=500),
    db: AsyncSession = Depends(get_db),
):
    """
    لیست کاربران با موقعیت مکانی برای نمایش روی کره زمین.
    اولویتِ موقعیت: GPS دقیق (metadata.geo_gps، به‌صورت محدوده) → IP (metadata.geo) → مرکز کشور.
    فقط کاربران با privacy_on_map=True نمایش داده می‌شوند.
    """
    conditions = [
        User.status == "active",
        User.privacy_on_map == True,
    ]
    if country:
        conditions.append(User.country_code == country.upper())

    result = await db.execute(
        select(
            User.earth_id,
            User.full_name,
            User.username,
            User.role,
            User.country_code,
            User.avg_rating,
            User.kyc_level,
            User.avatar_url,
            User.metadata_,
            User.last_login_at,
        )
        .where(and_(*conditions))
        .limit(limit)
    )
    rows = result.all()

    now = datetime.now(timezone.utc)
    online_cutoff = now - timedelta(minutes=15)

    users = []
    for r in rows:
        role = r.role or "user"
        if type and role != type:
            continue

        meta = r.metadata_ if isinstance(r.metadata_, dict) else {}
        gps = meta.get("geo_gps") if isinstance(meta, dict) else None
        geo = meta.get("geo") if isinstance(meta, dict) else None

        city = None
        if gps and gps.get("lat") is not None and gps.get("lng") is not None:
            # موقعیتِ دقیقِ GPS → به‌صورت محدوده برای نمایش عمومی
            lat, lng = _fuzz_area(r.earth_id, float(gps["lat"]), float(gps["lng"]))
            city = gps.get("city")
        elif geo and geo.get("lat") is not None and geo.get("lng") is not None:
            lat, lng = _seed_jitter(r.earth_id, float(geo["lat"]), float(geo["lng"]), 0.02)
            city = geo.get("city")
        else:
            cc = r.country_code or "IRN"
            base = _COUNTRY_COORDS.get(cc, (0.0, 0.0))
            lat, lng = _seed_jitter(r.earth_id, base[0], base[1], 2.5)

        last_login = r.last_login_at
        online = bool(last_login and last_login >= online_cutoff)

        users.append({
            "earth_id": r.earth_id,
            "name": r.full_name or r.username or r.earth_id,
            "role": role,
            "country_code": r.country_code or "IRN",
            "city": city,
            "lat": lat,
            "lng": lng,
            "rating": round((r.avg_rating or 0) / 100, 1),
            "kyc_level": r.kyc_level or 0,
            "avatar_url": r.avatar_url,
            "online": online,
        })

    return {"count": len(users), "users": users}
