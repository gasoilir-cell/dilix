#!/usr/bin/env python3
"""
بنچمارکِ ظرفیتِ /api/v1/calls/poll — سنجشِ اثرِ تعدادِ workerِ uvicorn.

روی خودِ سرور اجرا می‌شود (کلاینت یک هسته می‌خورد، پس عدد «کف» است نه سقف).
    python3 poll_bench.py --duration 20 --concurrency 64

توکن: با کلیدِ JWTِ خودِ اپ برای یک کاربرِ موجود ساخته می‌شود (بدونِ نوشتن در دیتابیس).
"""
import argparse
import asyncio
import statistics
import sys
import time

sys.path.insert(0, "/var/www/dilix-api")

import httpx  # noqa: E402


async def make_token() -> str:
    """توکنِ access برای اولین کاربرِ فعال (فقط خواندن از دیتابیس)."""
    from sqlalchemy import select
    from app.core.security import create_access_token
    from app.core.database import AsyncSessionLocal
    from app.models.user import User

    async with AsyncSessionLocal() as db:
        rows = (await db.execute(select(User).limit(20))).scalars().all()
        active = next((u for u in rows if u.is_active), None)
        if active is None:
            raise SystemExit("ERROR: هیچ کاربرِ فعالی در دیتابیس نیست")
        return create_access_token({"sub": str(active.id)})


async def worker(client, url, headers, stop_at, lat, res):
    while time.perf_counter() < stop_at:
        t0 = time.perf_counter()
        try:
            r = await client.get(url, headers=headers)
            lat.append((time.perf_counter() - t0) * 1000)
            res[r.status_code] = res.get(r.status_code, 0) + 1
        except Exception as e:  # noqa: BLE001
            res[type(e).__name__] = res.get(type(e).__name__, 0) + 1


async def main():
    p = argparse.ArgumentParser()
    p.add_argument("--duration", type=int, default=20)
    p.add_argument("--concurrency", type=int, default=64)
    p.add_argument("--base", default="http://127.0.0.1:8000")
    p.add_argument("--warmup", type=int, default=3)
    a = p.parse_args()

    token = await make_token()
    url = f"{a.base}/api/v1/calls/poll"
    headers = {"Authorization": f"Bearer {token}"}

    limits = httpx.Limits(
        max_connections=a.concurrency + 10, max_keepalive_connections=a.concurrency + 10
    )
    async with httpx.AsyncClient(limits=limits, timeout=15.0) as client:
        probe = await client.get(url, headers=headers)
        if probe.status_code != 200:
            print(f"ERROR: probe {probe.status_code} — {probe.text[:200]}")
            return 1

        # warm-up (خارج از آمار)
        wu_stop = time.perf_counter() + a.warmup
        await asyncio.gather(
            *[worker(client, url, headers, wu_stop, [], {}) for _ in range(a.concurrency)]
        )

        lat: list[float] = []
        res: dict = {}
        t_start = time.perf_counter()
        stop_at = t_start + a.duration
        await asyncio.gather(
            *[worker(client, url, headers, stop_at, lat, res) for _ in range(a.concurrency)]
        )
        elapsed = time.perf_counter() - t_start

    total = sum(v for k, v in res.items() if isinstance(k, int))
    errors = sum(v for k, v in res.items() if not isinstance(k, int)) + sum(
        v for k, v in res.items() if isinstance(k, int) and k >= 400
    )
    lat.sort()

    def pct(q):
        return lat[min(int(len(lat) * q), len(lat) - 1)] if lat else 0.0

    print(f"concurrency : {a.concurrency}")
    print(f"duration    : {elapsed:.1f}s")
    print(f"requests    : {total}")
    print(f"rps         : {total / elapsed:.1f}")
    print(f"errors      : {errors}")
    print(f"latency ms  : p50={pct(0.50):.0f}  p95={pct(0.95):.0f}  p99={pct(0.99):.0f}")
    print(f"mean ms     : {statistics.mean(lat):.0f}" if lat else "")
    print(f"status      : {res}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
