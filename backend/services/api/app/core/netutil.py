"""
Dilix — ابزار شبکه
استخراج IP واقعی کاربر از پشت reverse proxy / Cloudflare
"""
from __future__ import annotations

import ipaddress

from fastapi import Request


def _is_public(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return not (
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_reserved
        or addr.is_multicast
        or addr.is_unspecified
    )


def get_client_ip(request: Request) -> str | None:
    """
    IP واقعی کاربر را با درنظرگرفتن proxy برمی‌گرداند.
    ترتیب: Cloudflare → X-Forwarded-For (اولین IP عمومی) → X-Real-IP → client.host
    """
    cf = request.headers.get("cf-connecting-ip")
    if cf and _is_public(cf.strip()):
        return cf.strip()

    xff = request.headers.get("x-forwarded-for")
    if xff:
        parts = [p.strip() for p in xff.split(",") if p.strip()]
        for ip in parts:
            if _is_public(ip):
                return ip
        if parts:
            return parts[0]

    real = request.headers.get("x-real-ip")
    if real and real.strip():
        return real.strip()

    if request.client:
        return request.client.host
    return None
