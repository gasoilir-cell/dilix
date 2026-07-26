"""نصبِ سقفِ نرخ روی dilix-api (سرویسِ زنده، خارج از این مخزن).

روی سرور اجرا می‌شود:  ``python3 apply_ratelimit.py``
- از هر فایلی که دست می‌خورد نسخهٔ ``.bak-<timestamp>`` می‌گیرد (قراردادِ همان پروژه).
- idempotent است: اگر وصله قبلاً خورده باشد کاری نمی‌کند.
"""
from __future__ import annotations

import pathlib
import time

ROOT = pathlib.Path("/var/www/dilix-api")
STAMP = time.strftime("%Y%m%d-%H%M%S")

MAIN_IMPORT = "from app.core.ratelimit import RateLimited, hit as ratelimit_hit, rate_limit_ip, rule_for_path\n"

MAIN_MIDDLEWARE = '''

# ─── Rate Limit Middleware (auth) ─────────────────────────────
AUTH_PREFIX = "/api/v1/auth"


@app.middleware("http")
async def rate_limit_auth(request: Request, call_next):
    """سقفِ نرخ روی `/api/v1/auth/*` بر پایه‌ی IP.

    فقط متدهای تغییردهنده شمرده می‌شوند؛ خواندنِ پروفایل (GET /me) که اپ مرتب
    صدا می‌زند نباید به سقف بخورد.
    """
    if (
        request.url.path.startswith(AUTH_PREFIX)
        and request.method not in ("GET", "HEAD", "OPTIONS")
    ):
        try:
            await ratelimit_hit(
                f"ip:{request.url.path}",
                rate_limit_ip(request),
                rule_for_path(request.url.path),
            )
        except RateLimited as exc:
            # میان‌افزار بیرونِ محدوده‌ی exception handlerهاست، پس پاسخ را
            # مستقیم می‌سازیم — با همان قالبِ خطای بقیه‌ی API.
            return JSONResponse(
                status_code=429,
                headers={"Retry-After": str(exc.retry_after)},
                content={"detail": exc.as_detail()},
            )
    return await call_next(request)


# ─── Rate Limit Error Handler (route-level) ──────────────────
@app.exception_handler(RateLimited)
async def rate_limited_handler(request: Request, exc: RateLimited):
    return JSONResponse(
        status_code=429,
        headers={"Retry-After": str(exc.retry_after)},
        content={"detail": exc.as_detail()},
    )

'''

ROUTER_IMPORT = "from app.core.ratelimit import OTP_DESTINATION_RULE, hit as ratelimit_hit\n"

ROUTER_ANCHOR = '''    otp_service = OTPService(redis)
    result = await otp_service.send_otp(body.phone, body.purpose)
'''

ROUTER_PATCH = '''    # سقفِ ارسال به یک شماره، مستقل از IP: cooldownِ ۳۰ ثانیه‌ای به‌تنهایی یعنی
    # ۱۲۰ پیامک در ساعت روی شماره‌ی قربانی، و هر پیامک هزینه‌ی واقعی دارد.
    await ratelimit_hit(f"otp:send:{body.purpose}", body.phone, OTP_DESTINATION_RULE)

    otp_service = OTPService(redis)
    result = await otp_service.send_otp(body.phone, body.purpose)
'''


def backup(path: pathlib.Path) -> None:
    path.with_name(f"{path.name}.bak-{STAMP}").write_text(
        path.read_text(encoding="utf-8"), encoding="utf-8"
    )


def patch_main() -> str:
    path = ROOT / "app/main.py"
    src = path.read_text(encoding="utf-8")
    if "ratelimit" in src:
        return "main.py: قبلاً وصله خورده"
    backup(path)

    anchor_import = "from app.core.redis import close_redis\n"
    assert anchor_import in src, "لنگرِ importِ redis پیدا نشد"
    src = src.replace(anchor_import, anchor_import + MAIN_IMPORT, 1)

    anchor = '# ─── Global Error Handler ─────────────────────────────────────\n'
    assert anchor in src, "لنگرِ Global Error Handler پیدا نشد"
    src = src.replace(anchor, MAIN_MIDDLEWARE.lstrip("\n") + "\n" + anchor, 1)

    path.write_text(src, encoding="utf-8")
    return "main.py: وصله خورد"


def patch_router() -> str:
    path = ROOT / "app/api/v1/auth/router.py"
    src = path.read_text(encoding="utf-8")
    if "ratelimit" in src:
        return "auth/router.py: قبلاً وصله خورده"
    backup(path)

    anchor_import = "from app.core.redis import get_redis\n"
    assert anchor_import in src, "لنگرِ importِ redis پیدا نشد"
    src = src.replace(anchor_import, anchor_import + ROUTER_IMPORT, 1)

    assert ROUTER_ANCHOR in src, "لنگرِ send_otp پیدا نشد"
    src = src.replace(ROUTER_ANCHOR, ROUTER_PATCH, 1)

    path.write_text(src, encoding="utf-8")
    return "auth/router.py: وصله خورد"


if __name__ == "__main__":
    print(patch_main())
    print(patch_router())
