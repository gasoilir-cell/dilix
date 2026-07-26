"""
Dilix — سرویس موقعیت‌یابی
- geolocate(ip): IP → مختصات (fallback وقتی GPS نداریم)
- reverse_geocode(lat,lng): مختصاتِ GPS → نام شهر/استان
همه‌ی خطاها بی‌صدا هستند — هرگز نباید مسیر ورود/صفحه را بشکند.
"""
from __future__ import annotations

import ipaddress

import httpx
from fastapi import Request

from app.core.netutil import get_client_ip

# ISO alpha-2 → alpha-3 (کشورهای پرکاربرد؛ بقیه بدون تبدیل رها می‌شوند)
_A2_TO_A3: dict[str, str] = {
    "IR": "IRN", "AE": "ARE", "TR": "TUR", "DE": "DEU", "GB": "GBR",
    "JP": "JPN", "US": "USA", "CN": "CHN", "RU": "RUS", "IN": "IND",
    "PK": "PAK", "AF": "AFG", "IQ": "IRQ", "SA": "SAU", "QA": "QAT",
    "KW": "KWT", "BH": "BHR", "OM": "OMN", "AZ": "AZE", "KZ": "KAZ",
    "UZ": "UZB", "TM": "TKM", "AM": "ARM", "GE": "GEO", "FR": "FRA",
    "IT": "ITA", "ES": "ESP", "NL": "NLD", "CH": "CHE", "SE": "SWE",
    "NO": "NOR", "AU": "AUS", "CA": "CAN", "BR": "BRA", "ZA": "ZAF",
    "EG": "EGY", "NG": "NGA", "KR": "KOR", "SG": "SGP", "MY": "MYS",
    "TH": "THA", "ID": "IDN", "PH": "PHL", "VN": "VNM",
}

# cache ساده در حافظه: ip → dict | None
_cache: dict[str, dict | None] = {}


def _is_public(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return not (
        addr.is_private or addr.is_loopback or addr.is_link_local
        or addr.is_reserved or addr.is_multicast or addr.is_unspecified
    )


async def geolocate(ip: str | None) -> dict | None:
    """IP → {lat, lng, city, region, cc}. برای IP خصوصی/نامعتبر None."""
    if not ip or not _is_public(ip):
        return None
    if ip in _cache:
        return _cache[ip]

    data: dict | None = None
    try:
        async with httpx.AsyncClient(timeout=2.5) as client:
            resp = await client.get(
                f"http://ip-api.com/json/{ip}",
                params={"fields": "status,lat,lon,city,regionName,countryCode"},
            )
            j = resp.json()
            if j.get("status") == "success" and j.get("lat") is not None:
                cc2 = j.get("countryCode") or ""
                data = {
                    "lat": float(j["lat"]),
                    "lng": float(j["lon"]),
                    "city": j.get("city") or None,
                    "region": j.get("regionName") or None,
                    "cc": _A2_TO_A3.get(cc2, cc2 or None),
                }
    except Exception:
        data = None

    _cache[ip] = data
    return data


async def reverse_geocode(lat: float, lng: float) -> dict | None:
    """مختصاتِ GPS → {city, region, cc} با Nominatim (best-effort)."""
    try:
        async with httpx.AsyncClient(
            timeout=3.0, headers={"User-Agent": "DilixEarth/1.0 (dilix.ir)"}
        ) as client:
            resp = await client.get(
                "https://nominatim.openstreetmap.org/reverse",
                params={
                    "format": "json",
                    "lat": lat,
                    "lon": lng,
                    "zoom": 12,
                    "accept-language": "fa",
                },
            )
            j = resp.json()
            addr = j.get("address", {}) if isinstance(j, dict) else {}
            city = (
                addr.get("city") or addr.get("town") or addr.get("village")
                or addr.get("county") or addr.get("state")
            )
            cc2 = (addr.get("country_code") or "").upper()
            return {
                "city": city or None,
                "region": addr.get("state") or None,
                "cc": _A2_TO_A3.get(cc2, cc2 or None),
            }
    except Exception:
        return None


async def record_login_geo(user, request: Request) -> None:
    """
    IP واقعی و موقعیتِ تقریبی را روی کاربر ثبت می‌کند (best-effort).
    نتیجه در ستون metadata_ ذخیره می‌شود تا نیازی به migration نباشد.
    این fallback است؛ اگر GPS ثبت شده باشد در نمایش اولویت با GPS است.
    """
    ip = get_client_ip(request)
    user.last_login_ip = ip

    try:
        geo = await geolocate(ip)
    except Exception:
        geo = None

    if geo:
        meta = dict(user.metadata_ or {})
        meta["geo"] = {
            "lat": geo["lat"],
            "lng": geo["lng"],
            "city": geo["city"],
            "region": geo["region"],
            "cc": geo["cc"],
            "ip": ip,
        }
        user.metadata_ = meta
        if geo["cc"] and not user.country_code:
            user.country_code = geo["cc"]
