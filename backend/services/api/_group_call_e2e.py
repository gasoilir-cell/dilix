"""E2E: تماسِ گروهی (roster) — invite/peer-join/members/cap/peer-left.

چرا اسکریپت و نه pytest؟ سرویسِ `api` مجموعهٔ pytest ندارد و منطقِ roster فقط با
Redisِ واقعی معنا دارد (حضور، TTL، صفِ سیگنال). هم‌سبکِ `_poll_e2e.py`.

اجرا (روی سرور، کنارِ سورس):
    BASE=http://127.0.0.1:8011/api/v1 venv/bin/python _group_call_e2e.py
"""
import asyncio
import os

import httpx
from sqlalchemy import select

from app.core.database import AsyncSessionLocal, engine
from app.core.security import create_access_token
from app.models.user import User

BASE = os.environ.get("BASE", "http://127.0.0.1:8000/api/v1")
SDP = '{"type":"offer","sdp":"v=0\\r\\n"}'

passed = 0
failed = 0


def check(cond, label):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}")


async def poll(c, h):
    """هم صفِ سیگنال را می‌خوانَد و هم حضور را تازه می‌کند (invite بدونِ آن offline می‌دهد)."""
    r = await c.get(f"{BASE}/calls/poll", headers=h)
    return r.json()["signals"]


async def main():
    async with AsyncSessionLocal() as db:
        users = (await db.execute(select(User).limit(8))).scalars().all()
    if len(users) < 8:
        print(f"! فقط {len(users)} کاربر — تستِ سقف رد می‌شود")
    hdr = {
        u.earth_id: {"Authorization": f"Bearer {create_access_token({'sub': str(u.id)})}"}
        for u in users
    }
    ids = [u.earth_id for u in users]
    A, B, C, D = ids[0], ids[1], ids[2], ids[3]

    async with httpx.AsyncClient(timeout=20) as c:
        # همه آنلاین شوند و صفِ کهنه خالی شود
        for eid in ids:
            await poll(c, hdr[eid])

        # ── ۱:۱ ──
        r = await c.post(f"{BASE}/calls/invite",
                         json={"to_earth_id": B, "media": "audio", "sdp": SDP},
                         headers=hdr[A])
        check(r.status_code == 200, f"invite 200 ({r.status_code})")
        j = r.json()
        check(j["status"] == "ringing", f"status ringing ({j.get('status')})")
        call_id = j["call_id"]
        check(sorted(j["members"]) == sorted([A, B]), f"members=[A,B] ({j['members']})")

        sig = await poll(c, hdr[B])
        inc = next((s for s in sig if s["type"] == "incoming"), None)
        check(inc is not None, "B گرفت: incoming")
        check(inc and inc["members"] == [], f"incoming.members خالی ({inc and inc['members']})")

        # ── نفرِ سوم ──
        r = await c.post(f"{BASE}/calls/invite",
                         json={"to_earth_id": C, "media": "audio",
                               "sdp": SDP, "call_id": call_id},
                         headers=hdr[A])
        check(r.status_code == 200, f"invite#3 200 ({r.status_code})")
        check(sorted(r.json()["members"]) == sorted([A, B, C]), "members=[A,B,C]")

        sig = await poll(c, hdr[C])
        inc = next((s for s in sig if s["type"] == "incoming"), None)
        check(inc is not None, "C گرفت: incoming")
        check(inc and sorted(inc["members"]) == sorted([A, B]),
              f"C می‌داند دو عضوِ دیگر هست ({inc and inc['members']})")

        sig = await poll(c, hdr[B])
        pj = next((s for s in sig if s["type"] == "peer-join"), None)
        check(pj is not None, "B گرفت: peer-join")
        check(pj and pj["peer"] == C, f"peer-join.peer == C ({pj and pj.get('peer')})")

        # A نباید peer-join بگیرد (خودش دعوت کرده)
        sig = await poll(c, hdr[A])
        check(not [s for s in sig if s["type"] == "peer-join"], "A سیگنالِ peer-join نگرفت")

        # ── /members ──
        r = await c.get(f"{BASE}/calls/{call_id}/members", headers=hdr[A])
        check(r.status_code == 200 and sorted(r.json()["members"]) == sorted([A, B, C]),
              f"GET members ({r.status_code})")

        r = await c.get(f"{BASE}/calls/{call_id}/members", headers=hdr[D])
        check(r.status_code == 403, f"غیرعضو members 403 ({r.status_code})")

        # ── منفی‌ها ──
        r = await c.post(f"{BASE}/calls/invite",
                         json={"to_earth_id": B, "sdp": SDP, "call_id": call_id},
                         headers=hdr[A])
        check(r.status_code == 409, f"دعوتِ تکراری 409 ({r.status_code})")

        r = await c.post(f"{BASE}/calls/invite",
                         json={"to_earth_id": ids[4], "sdp": SDP, "call_id": call_id},
                         headers=hdr[D])
        check(r.status_code == 403, f"دعوت توسطِ غیرعضو 403 ({r.status_code})")

        r = await c.post(f"{BASE}/calls/invite",
                         json={"to_earth_id": A, "sdp": SDP}, headers=hdr[A])
        check(r.status_code == 400, f"زنگ به خود 400 ({r.status_code})")

        # ── سقفِ اعضا ──
        if len(ids) >= 8:
            for extra in ids[3:6]:          # → ۶ نفر
                r = await c.post(f"{BASE}/calls/invite",
                                 json={"to_earth_id": extra, "sdp": SDP,
                                       "call_id": call_id}, headers=hdr[A])
                check(r.status_code == 200, f"افزودنِ {extra} ({r.status_code})")
            r = await c.post(f"{BASE}/calls/invite",
                             json={"to_earth_id": ids[6], "sdp": SDP,
                                   "call_id": call_id}, headers=hdr[A])
            check(r.status_code == 409, f"عبور از سقفِ ۶ نفر → 409 ({r.status_code})")

        # ── خروجِ یک عضو ──
        r = await c.post(f"{BASE}/calls/signal",
                         json={"call_id": call_id, "to_earth_id": A,
                               "type": "peer-left"}, headers=hdr[C])
        check(r.status_code == 200, f"peer-left 200 ({r.status_code})")

        r = await c.get(f"{BASE}/calls/{call_id}/members", headers=hdr[A])
        check(C not in r.json()["members"], f"C از فهرست حذف شد ({r.json()['members']})")

        sig = await poll(c, hdr[A])
        check(any(s["type"] == "peer-left" and s["from"] == C for s in sig),
              "A گرفت: peer-left از C")

        # سیگنالِ نامعتبر
        r = await c.post(f"{BASE}/calls/signal",
                         json={"call_id": call_id, "to_earth_id": B,
                               "type": "bogus"}, headers=hdr[A])
        check(r.status_code == 400, f"نوعِ سیگنالِ نامعتبر 400 ({r.status_code})")

        # اشتراکِ صفحه یک نوعِ معتبر است
        r = await c.post(f"{BASE}/calls/signal",
                         json={"call_id": call_id, "to_earth_id": B,
                               "type": "screen", "text": "on"}, headers=hdr[A])
        check(r.status_code == 200, f"سیگنالِ screen 200 ({r.status_code})")
        sig = await poll(c, hdr[B])
        check(any(s["type"] == "screen" and s["text"] == "on" for s in sig),
              "B گرفت: screen=on")

        # نظافت: بقیه هم خارج شوند تا کلیدِ roster نمانَد
        for eid in ids[:6]:
            await c.post(f"{BASE}/calls/signal",
                         json={"call_id": call_id, "to_earth_id": A,
                               "type": "peer-left"}, headers=hdr[eid])

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())
