#!/usr/bin/env python3
"""
سنجشِ هزینهٔ کاربرِ بی‌کار: WebSocket در برابرِ pollِ ۱.۵ثانیه‌ای.

چه چیزی اندازه می‌گیرد: N کاربرِ بی‌کارِ هم‌زمان را شبیه‌سازی می‌کند و **CPUِ خودِ
سرویس** را می‌سنجد (از /proc، نه از دیدِ کلاینت). این عدد است که سقفِ کاربرِ
هم‌زمان را تعیین می‌کند، نه rps؛ چون در حالتِ poll ~۹۹٪ درخواست‌ها خالی‌اند و
فقط CPU می‌سوزانند.

    python3 ws_bench.py --mode ws   --conns 500 --duration 30
    python3 ws_bench.py --mode poll --conns 500 --duration 30

مقایسه فقط وقتی معتبر است که هر دو حالت با یک `--conns` و یک `--duration`
اجرا شوند و CPUِ کلاینت اشباع نشده باشد (در خروجی گزارش می‌شود).
"""
import argparse
import asyncio
import base64
import os
import resource
import sys
import time

sys.path.insert(0, "/var/www/dilix-api")

HOST = "127.0.0.1"
PORT = 8000
POLL_INTERVAL = 1.5  # همان آهنگِ کلاینتِ قدیمی


async def make_tokens(distinct: bool) -> list[str]:
    """
    توکنِ access. با `distinct` توکنِ همهٔ کاربرانِ فعال برمی‌گردد.

    چرا مهم است: با یک کاربر، hubِ سرور فقط روی **یک** کانال مشترک می‌شود و
    هزینهٔ چندکاناله دیده نمی‌شود. حالتِ distinct کانال‌های متمایز می‌سازد تا
    عددِ ظرفیت بیش‌ازواقع خوش‌بینانه نباشد.
    """
    from sqlalchemy import select
    from app.core.security import create_access_token
    from app.core.database import AsyncSessionLocal
    from app.models.user import User

    async with AsyncSessionLocal() as db:
        limit = 500 if distinct else 20
        rows = (await db.execute(select(User).limit(limit))).scalars().all()
    active = [u for u in rows if u.is_active]
    if not active:
        raise SystemExit("ERROR: هیچ کاربرِ فعالی در دیتابیس نیست")
    if not distinct:
        active = active[:1]
    return [create_access_token({"sub": str(u.id)}) for u in active]


CGROUP = "/sys/fs/cgroup/system.slice/dilix-api.service/cpu.stat"


def service_cpu_seconds() -> float:
    """
    زمانِ CPUِ کلِ سرویس از شمارندهٔ cgroupِ systemd.

    چرا cgroup و نه pgrep: مستر و هر ۴ workerِ uvicorn پروسه‌های جداگانه‌اند و
    الگوی pgrep فقط مستر را می‌گرفت (و بدتر، dilix-coreِ بی‌ربط را هم می‌گرفت).
    cgroup دقیقاً مرزِ همین سرویس است و هیچ فرزندی از قلم نمی‌افتد.
    """
    with open(CGROUP, encoding="utf-8") as f:
        for line in f:
            if line.startswith("usage_usec"):
                return int(line.split()[1]) / 1e6
    raise SystemExit(f"ERROR: usage_usec در {CGROUP} نبود")


# ─── حالتِ WebSocket ────────────────────────────────────────────
async def _read_frame(reader) -> tuple[int, bytes]:
    """یک فریمِ WS را می‌خوانَد و (opcode, payload) می‌دهد. سرور ماسک نمی‌زند."""
    hdr = await reader.readexactly(2)
    opcode = hdr[0] & 0x0F
    masked = hdr[1] & 0x80
    ln = hdr[1] & 0x7F
    if ln == 126:
        ln = int.from_bytes(await reader.readexactly(2), "big")
    elif ln == 127:
        ln = int.from_bytes(await reader.readexactly(8), "big")
    mask = await reader.readexactly(4) if masked else b""
    data = await reader.readexactly(ln) if ln else b""
    if masked:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return opcode, data


def _frame(opcode: int, payload: bytes = b"") -> bytes:
    """فریمِ سمتِ کلاینت — طبقِ RFC 6455 حتماً باید ماسک‌دار باشد."""
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked


async def ws_client(token: str, stop_at: float, stats: dict):
    """
    یک کاربرِ بی‌کار روی WebSocket.

    نکتهٔ حیاتی: کلاینت باید به فریمِ ping سرور با pong جواب بدهد. uvicorn هر
    ۲۰ثانیه ping می‌فرستد و اگر جواب نگیرد اتصال را تمیز می‌بندد؛ نسخهٔ اولِ این
    اسکریپت بایت‌ها را دور می‌ریخت و به همین دلیل همهٔ اتصال‌ها حوالیِ ثانیهٔ ۲۰
    می‌مردند — که ایرادِ سنجه بود، نه ایرادِ سرور.
    """
    writer = None
    try:
        reader, writer = await asyncio.open_connection(HOST, PORT)
        key = base64.b64encode(os.urandom(16)).decode()
        writer.write(
            (
                f"GET /api/v1/ws?token={token} HTTP/1.1\r\n"
                f"Host: {HOST}:{PORT}\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
            ).encode()
        )
        await writer.drain()
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=20)
        if b"101" not in head.split(b"\r\n")[0]:
            stats["fail"] = stats.get("fail", 0) + 1
            return
        stats["open"] = stats.get("open", 0) + 1

        while time.perf_counter() < stop_at:
            try:
                opcode, data = await asyncio.wait_for(_read_frame(reader), timeout=1.0)
            except asyncio.TimeoutError:
                continue
            stats["frames"] = stats.get("frames", 0) + 1
            if opcode == 0x9:      # ping → باید pong بدهیم
                writer.write(_frame(0xA, data))
                await writer.drain()
                stats["pong"] = stats.get("pong", 0) + 1
            elif opcode == 0x8:    # close
                stats["closed_by_server"] = stats.get("closed_by_server", 0) + 1
                break
    except Exception as e:  # noqa: BLE001
        stats[type(e).__name__] = stats.get(type(e).__name__, 0) + 1
    finally:
        if writer is not None:
            writer.close()


# ─── حالتِ poll ─────────────────────────────────────────────────
async def poll_client(req: bytes, stop_at: float, stats: dict):
    reader = writer = None
    while time.perf_counter() < stop_at:
        try:
            if writer is None:
                reader, writer = await asyncio.open_connection(HOST, PORT)
            writer.write(req)
            await writer.drain()
            head = await reader.readuntil(b"\r\n\r\n")
            clen = 0
            for line in head.split(b"\r\n"):
                if line[:15].lower() == b"content-length:":
                    clen = int(line[15:])
                    break
            if clen:
                await reader.readexactly(clen)
            stats["req"] = stats.get("req", 0) + 1
        except Exception as e:  # noqa: BLE001
            stats[type(e).__name__] = stats.get(type(e).__name__, 0) + 1
            if writer is not None:
                writer.close()
            writer = None
        await asyncio.sleep(POLL_INTERVAL)
    if writer is not None:
        writer.close()


async def run(mode: str, conns: int, duration: int, distinct: bool):
    tokens = await make_tokens(distinct)
    stats: dict = {}
    stop_at = time.perf_counter() + duration

    if mode == "ws":
        tasks = [
            ws_client(tokens[i % len(tokens)], stop_at, stats) for i in range(conns)
        ]
    else:
        def req_for(tok: str) -> bytes:
            return (
                "GET /api/v1/calls/poll HTTP/1.1\r\n"
                f"Host: {HOST}:{PORT}\r\n"
                f"Authorization: Bearer {tok}\r\n"
                "Accept: application/json\r\nConnection: keep-alive\r\n\r\n"
            ).encode()

        tasks = [
            poll_client(req_for(tokens[i % len(tokens)]), stop_at, stats)
            for i in range(conns)
        ]

    # نمونهٔ CPU بعد از برقراریِ اتصال‌ها گرفته می‌شود تا هزینهٔ یک‌بارهٔ
    # دست‌دادن با هزینهٔ دائمیِ «بی‌کار ماندن» قاطی نشود.
    runner = asyncio.gather(*tasks)
    await asyncio.sleep(min(5, duration // 3))
    cpu0, t0 = service_cpu_seconds(), time.perf_counter()
    ru0 = resource.getrusage(resource.RUSAGE_SELF)
    await runner
    cpu1, t1 = service_cpu_seconds(), time.perf_counter()
    ru1 = resource.getrusage(resource.RUSAGE_SELF)

    window = t1 - t0
    srv = (cpu1 - cpu0) / window
    cli = ((ru1.ru_utime - ru0.ru_utime) + (ru1.ru_stime - ru0.ru_stime)) / window

    print(f"mode          : {mode}{'  (distinct users)' if distinct else ''}")
    print(f"conns         : {conns}  (tokens: {len(tokens)})")
    print(f"window        : {window:.1f}s")
    print(f"server CPU    : {srv:.3f} core   ← معیارِ اصلی")
    print(f"per 1k users  : {srv / conns * 1000:.3f} core")
    print(f"client CPU    : {cli:.3f} core  ({os.cpu_count()} available)")
    print(f"stats         : {stats}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["ws", "poll"], default="ws")
    p.add_argument("--conns", type=int, default=500)
    p.add_argument("--duration", type=int, default=30)
    p.add_argument(
        "--distinct",
        action="store_true",
        help="پخشِ اتصال‌ها روی کاربرانِ متمایز (کانال‌های متمایزِ pub/sub)",
    )
    a = p.parse_args()
    asyncio.run(run(a.mode, a.conns, a.duration, a.distinct))


if __name__ == "__main__":
    main()
