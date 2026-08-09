#!/usr/bin/env python3
"""
E2E واقعیِ WebSocketِ سیگنالینگ — روی سرویسِ زنده اجرا می‌شود.

نکتهٔ اصلی که می‌سنجد: فرستنده و گیرنده روی **دو workerِ متفاوت** هستند، پس اگر
مسیرِ pub/sub یا درِینِ صف خراب باشد سیگنال هرگز نمی‌رسد. تستِ تک‌پروسه‌ای این را
نمی‌گیرد.

    cd /var/www/dilix-api && ./venv/bin/python /root/ws_e2e.py

با `--base`/`--ws` همین سوییت از راهِ پروکسیِ عمومی هم اجرا می‌شود (مسیرِ واقعیِ مرورگر):

    ... /root/ws_e2e.py --base https://dilix.ir --ws wss://dilix.ir/api/v1/ws
"""
import argparse
import asyncio
import json
import sys

sys.path.insert(0, "/var/www/dilix-api")

import httpx  # noqa: E402
import websockets  # noqa: E402

BASE = "http://127.0.0.1:8000"
WS = "ws://127.0.0.1:8000/api/v1/ws"

ok = 0
fail = 0


def check(name: str, cond: bool, extra: str = "") -> None:
    global ok, fail
    if cond:
        ok += 1
        print(f"  ✓ {name}")
    else:
        fail += 1
        print(f"  ✗ {name}  {extra}")


async def two_users():
    """دو کاربرِ واقعی از دیتابیس + توکنِ access هرکدام."""
    from sqlalchemy import select
    from app.core.security import create_access_token
    from app.core.database import AsyncSessionLocal
    from app.models.user import User

    async with AsyncSessionLocal() as db:
        rows = (await db.execute(select(User).limit(40))).scalars().all()
    act = [u for u in rows if u.is_active][:2]
    if len(act) < 2:
        raise SystemExit("ERROR: برای تست به دو کاربرِ فعال نیاز است")
    return [(u.earth_id, create_access_token({"sub": str(u.id)})) for u in act]


async def recv_json(ws, timeout=5.0):
    raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
    if raw == "pong":
        return {"type": "pong"}
    return json.loads(raw)


async def main():
    (a_earth, a_tok), (b_earth, b_tok) = await two_users()
    print(f"A={a_earth}  B={b_earth}\n")

    print("۱) رد کردنِ توکنِ نامعتبر")
    try:
        async with websockets.connect(f"{WS}?token=garbage"):
            check("توکنِ نامعتبر باید رد شود", False, "اتصال برقرار شد!")
    except Exception as e:  # noqa: BLE001
        check("توکنِ نامعتبر رد شد", "4001" in str(e) or "rejected" in str(e).lower(), str(e)[:80])

    print("\n۲) اتصال، پیامِ ready و heartbeatِ حضور")
    async with websockets.connect(f"{WS}?token={b_tok}") as wsb:
        first = await recv_json(wsb)
        # ممکن است ابتدا صفِ جامانده بیاید، سپس ready
        if first.get("type") == "signals":
            first = await recv_json(wsb)
        check("پیامِ ready آمد", first.get("type") == "ready", str(first)[:80])
        check("earth_id درست است", first.get("earth_id") == b_earth, str(first)[:80])

        # حضور باید بدونِ هیچ pollـی ثبت شده باشد
        from app.core.redis import get_redis
        r = await get_redis()
        seen = await r.get("calls:seen:" + b_earth)
        check("کلیدِ حضور بدونِ poll ست شد", seen == "1", f"seen={seen}")

        print("\n۳) ping/pong")
        await wsb.send("ping")
        pong = await recv_json(wsb)
        check("pong دریافت شد", pong.get("type") == "pong", str(pong)[:60])

        print("\n۴) تحویلِ سیگنال از A به B — بینِ دو workerِ متفاوت")
        async with httpx.AsyncClient(base_url=BASE, timeout=15.0) as c:
            res = await c.post(
                "/api/v1/calls/invite",
                headers={"Authorization": f"Bearer {a_tok}"},
                json={"to_earth_id": b_earth, "media": "audio", "sdp": json.dumps({"type": "offer", "sdp": "v=0-test"})},
            )
            check("invite پذیرفته شد", res.status_code == 200, f"{res.status_code} {res.text[:100]}")
            body = res.json()
            check("وضعیت ringing است (یعنی B آنلاین دیده شد)",
                  body.get("status") == "ringing", str(body)[:120])
            call_id = body.get("call_id")

            try:
                msg = await recv_json(wsb, timeout=6.0)
                sigs = msg.get("signals", [])
                check("سیگنال از راهِ WebSocket رسید", msg.get("type") == "signals" and len(sigs) > 0, str(msg)[:100])
                if sigs:
                    check("نوعِ سیگنال incoming است", sigs[0].get("type") == "incoming", str(sigs[0])[:100])
                    check("فرستنده A است", sigs[0].get("from") == a_earth, str(sigs[0])[:100])
            except asyncio.TimeoutError:
                check("سیگنال از راهِ WebSocket رسید", False, "تایم‌اوت ۶ ثانیه")

            print("\n۵) صف نباید دوباره تحویل شود (تحویلِ حداکثر یک‌بار)")
            poll = await c.get("/api/v1/calls/poll", headers={"Authorization": f"Bearer {b_tok}"})
            left = poll.json().get("signals", [])
            check("صف پس از تحویلِ WS خالی است", len(left) == 0, f"{len(left)} سیگنالِ تکراری مانده")

            print("\n۶) سیگنالِ دوم (ice) هم زنده می‌رسد")
            await c.post(
                "/api/v1/calls/signal",
                headers={"Authorization": f"Bearer {a_tok}"},
                json={"call_id": call_id, "to_earth_id": b_earth, "type": "ice",
                      "sdp": json.dumps({"candidate": "cand-test"})},
            )
            try:
                msg2 = await recv_json(wsb, timeout=6.0)
                s2 = msg2.get("signals", [])
                check("سیگنالِ ice رسید", len(s2) > 0 and s2[0].get("type") == "ice", str(msg2)[:100])
            except asyncio.TimeoutError:
                check("سیگنالِ ice رسید", False, "تایم‌اوت")

    print("\n۷) بعد از قطعِ WS، مسیرِ poll هنوز کار می‌کند (fallback)")
    async with httpx.AsyncClient(base_url=BASE, timeout=15.0) as c:
        await c.post(
            "/api/v1/calls/signal",
            headers={"Authorization": f"Bearer {a_tok}"},
            json={"call_id": "x", "to_earth_id": b_earth, "type": "end"},
        )
        await asyncio.sleep(0.3)
        poll = await c.get("/api/v1/calls/poll", headers={"Authorization": f"Bearer {b_tok}"})
        sigs = poll.json().get("signals", [])
        check("سیگنال از راهِ poll رسید", any(s.get("type") == "end" for s in sigs), str(sigs)[:120])

    print(f"\n{'='*46}\nنتیجه: {ok} سبز / {fail} قرمز")
    return 1 if fail else 0


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--base", default=BASE, help="ریشهٔ HTTP (پیش‌فرض: مستقیم روی 8000)")
    p.add_argument("--ws", default=WS, help="آدرسِ کاملِ WebSocket")
    a = p.parse_args()
    BASE, WS = a.base, a.ws
    print(f"BASE={BASE}  WS={WS}\n")
    raise SystemExit(asyncio.run(main()))
