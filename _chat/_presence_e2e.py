"""E2E: حضور (آنلاین/آخرین‌بازدید) + «در حال نوشتن»."""
import asyncio
import httpx
from sqlalchemy import select, text

from app.core.database import AsyncSessionLocal, engine
from app.models.user import User
from app.core.security import create_access_token

BASE = "http://127.0.0.1:8000/api/v1"
A_EID = "DLX-OO39V4SY"
B_EID = "DLX-CSV157XM"

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


async def main():
    async with AsyncSessionLocal() as db:
        A = (await db.execute(select(User).where(User.earth_id == A_EID))).scalar_one()
        B = (await db.execute(select(User).where(User.earth_id == B_EID))).scalar_one()
        a_id, b_id = str(A.id), str(B.id)

    ta = create_access_token({"sub": a_id})
    tb = create_access_token({"sub": b_id})
    ha = {"Authorization": f"Bearer {ta}"}
    hb = {"Authorization": f"Bearer {tb}"}

    async with httpx.AsyncClient(timeout=15) as c:
        # اتاقِ direct بین A و B
        r = await c.post(f"{BASE}/messages/rooms", json={"earth_id": B_EID}, headers=ha)
        check(r.status_code in (200, 201), f"create/get direct room ({r.status_code})")
        room_id = r.json()["id"]

        # A وضعیتِ اتاق را می‌گیرد → حضورِ A تازه می‌شود
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/status", headers=ha)
        check(r.status_code == 200, f"A status 200 ({r.status_code})")
        check("typing" in r.json(), "status has typing[]")

        # B وضعیت را می‌گیرد → باید A را آنلاین ببیند (چون A تازه ping زد)
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/status", headers=hb)
        js = r.json()
        check(js.get("partner_online") is True, "B sees A online")
        check(js.get("partner_last_seen") is not None, "B sees A last_seen")

        # A اعلامِ در حال نوشتن می‌کند
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/typing", headers=ha)
        check(r.status_code == 204, f"A typing 204 ({r.status_code})")

        # B وضعیت → typing شاملِ نامِ A
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/status", headers=hb)
        js = r.json()
        a_name = A.full_name or A.username or A.earth_id
        check(a_name in js.get("typing", []), f"B sees A typing ({js.get('typing')})")

        # B در لیستِ اتاق‌ها partner_online برای A را می‌بیند
        r = await c.get(f"{BASE}/messages/rooms", headers=hb)
        rooms = r.json()
        target = next((x for x in rooms if x["id"] == room_id), None)
        check(target is not None, "room appears in B list")
        check(target and "partner_online" in target, "list has partner_online field")

        # منفی: غیرعضو نمی‌تواند status/typing بگیرد
        # کاربرِ سوم لازم است؛ اگر نبود این دو چک رد می‌شوند اما بی‌خطر
        async with AsyncSessionLocal() as db:
            third = (await db.execute(
                select(User).where(User.earth_id.notin_([A_EID, B_EID])).limit(1)
            )).scalar_one_or_none()
        if third:
            tc = create_access_token({"sub": str(third.id)})
            hc = {"Authorization": f"Bearer {tc}"}
            r = await c.get(f"{BASE}/messages/rooms/{room_id}/status", headers=hc)
            check(r.status_code == 403, f"non-member status 403 ({r.status_code})")
            r = await c.post(f"{BASE}/messages/rooms/{room_id}/typing", headers=hc)
            check(r.status_code == 403, f"non-member typing 403 ({r.status_code})")

        # منفی: اتاقِ نامعتبر → 400
        r = await c.get(f"{BASE}/messages/rooms/not-a-uuid/status", headers=ha)
        check(r.status_code == 400, f"invalid room 400 ({r.status_code})")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())
