#!/usr/bin/env python3
"""
بنچمارکِ سبکِ /api/v1/calls/poll با سوکتِ خام.

چرا سوکتِ خام: کلاینتِ httpx خودش ~۱۰۰٪ یک هسته می‌خورد و روی ماشینِ ۴ هسته‌ای
عملاً کلاینت را می‌سنجد نه سرور. اینجا درخواست از قبل به بایت تبدیل می‌شود و
پاسخ فقط تا Content-Length خوانده می‌شود → هزینهٔ کلاینت چند برابر کمتر.

    python3 poll_bench_raw.py --duration 20 --concurrency 64 --procs 2

`--procs` چند پروسهٔ کلاینت را موازی اجرا می‌کند (برای عبور از سقفِ GIL).
خروجی شاملِ «CPU کلاینت» است تا معلوم باشد اندازه‌گیری معتبر است یا خودِ
کلاینت اشباع شده.
"""
import argparse
import asyncio
import multiprocessing as mp
import os
import resource
import sys
import time

sys.path.insert(0, "/var/www/dilix-api")

HOST = "127.0.0.1"
PORT = 8000


async def make_token() -> str:
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


async def conn_worker(req: bytes, stop_at: float, lat: list, counts: dict):
    reader = writer = None
    while time.perf_counter() < stop_at:
        try:
            if writer is None:
                reader, writer = await asyncio.open_connection(HOST, PORT)
            t0 = time.perf_counter()
            writer.write(req)
            await writer.drain()

            # هدر تا CRLFCRLF
            head = await reader.readuntil(b"\r\n\r\n")
            status = int(head[9:12])
            clen = 0
            for line in head.split(b"\r\n"):
                if line[:15].lower() == b"content-length:":
                    clen = int(line[15:])
                    break
            if clen:
                await reader.readexactly(clen)
            lat.append((time.perf_counter() - t0) * 1000)
            counts[status] = counts.get(status, 0) + 1
            if b"close" in head.lower():
                writer.close()
                writer = None
        except Exception as e:  # noqa: BLE001
            counts[type(e).__name__] = counts.get(type(e).__name__, 0) + 1
            if writer is not None:
                try:
                    writer.close()
                except Exception:  # noqa: BLE001
                    pass
            writer = None
            await asyncio.sleep(0.005)
    if writer is not None:
        try:
            writer.close()
        except Exception:  # noqa: BLE001
            pass


async def run_proc(token: str, duration: int, concurrency: int, warmup: int, q):
    req = (
        f"GET /api/v1/calls/poll HTTP/1.1\r\n"
        f"Host: {HOST}:{PORT}\r\n"
        f"Authorization: Bearer {token}\r\n"
        f"Accept: application/json\r\n"
        f"Connection: keep-alive\r\n\r\n"
    ).encode()

    if warmup:
        wu = time.perf_counter() + warmup
        await asyncio.gather(*[conn_worker(req, wu, [], {}) for _ in range(concurrency)])

    lat: list = []
    counts: dict = {}
    cpu0 = resource.getrusage(resource.RUSAGE_SELF)
    t0 = time.perf_counter()
    await asyncio.gather(
        *[conn_worker(req, t0 + duration, lat, counts) for _ in range(concurrency)]
    )
    elapsed = time.perf_counter() - t0
    cpu1 = resource.getrusage(resource.RUSAGE_SELF)
    cpu = (cpu1.ru_utime - cpu0.ru_utime) + (cpu1.ru_stime - cpu0.ru_stime)
    q.put({"lat": lat, "counts": counts, "elapsed": elapsed, "cpu": cpu})


def proc_main(token, duration, concurrency, warmup, q):
    asyncio.run(run_proc(token, duration, concurrency, warmup, q))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--duration", type=int, default=20)
    p.add_argument("--concurrency", type=int, default=64, help="در هر پروسه")
    p.add_argument("--procs", type=int, default=1)
    p.add_argument("--warmup", type=int, default=3)
    a = p.parse_args()

    token = asyncio.run(make_token())

    q = mp.Queue()
    procs = [
        mp.Process(
            target=proc_main, args=(token, a.duration, a.concurrency, a.warmup, q)
        )
        for _ in range(a.procs)
    ]
    for pr in procs:
        pr.start()
    results = [q.get() for _ in procs]
    for pr in procs:
        pr.join()

    lat = sorted(x for r in results for x in r["lat"])
    counts: dict = {}
    for r in results:
        for k, v in r["counts"].items():
            counts[k] = counts.get(k, 0) + v
    elapsed = max(r["elapsed"] for r in results)
    client_cpu = sum(r["cpu"] for r in results)

    ok = sum(v for k, v in counts.items() if isinstance(k, int) and k < 400)
    bad = sum(v for k, v in counts.items() if not isinstance(k, int)) + sum(
        v for k, v in counts.items() if isinstance(k, int) and k >= 400
    )

    def pct(qq):
        return lat[min(int(len(lat) * qq), len(lat) - 1)] if lat else 0.0

    total_conc = a.concurrency * a.procs
    print(f"concurrency  : {total_conc} ({a.procs} proc × {a.concurrency})")
    print(f"duration     : {elapsed:.1f}s")
    print(f"ok / errors  : {ok} / {bad}")
    print(f"rps          : {ok / elapsed:.1f}")
    print(f"latency ms   : p50={pct(0.50):.0f}  p95={pct(0.95):.0f}  p99={pct(0.99):.0f}")
    print(f"client CPU   : {client_cpu / elapsed:.2f} core  ({os.cpu_count()} available)")
    print(f"status       : {counts}")


if __name__ == "__main__":
    main()
