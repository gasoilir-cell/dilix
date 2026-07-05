"""E2E: in-chat message search — Dilix messenger."""
import asyncio
import httpx
from sqlalchemy import text, select
from app.core.database import AsyncSessionLocal, engine
from app.core.security import create_access_token
from app.models.user import User

BASE = "http://localhost:8000/api/v1/messages"
PASS = 0
FAIL = 0


def check(cond, label):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


async def get_users():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.earth_id.in_(["DLX-OO39V4SY", "DLX-CSV157XM"])))
        rows = {u.earth_id: u for u in res.scalars().all()}
        return rows["DLX-OO39V4SY"], rows["DLX-CSV157XM"]


async def main():
    A, B = await get_users()
    haA = {"Authorization": f"Bearer {create_access_token({'sub': str(A.id)})}"}
    haB = {"Authorization": f"Bearer {create_access_token({'sub': str(B.id)})}"}

    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(f"{BASE}/rooms", headers=haA, json={"earth_id": B.earth_id})
        direct_id = r.json()["id"]

        token = "زرافه‌بنفش۹۹۱۷"  # عبارتِ یکتا
        r = await c.post(f"{BASE}/rooms/{direct_id}/messages", headers=haB, json={"content": f"سلام این پیام شاملِ {token} است"})
        check(r.status_code in (200, 201), f"B send unique msg ({r.status_code})")
        msg_id = r.json()["id"]
        await c.post(f"{BASE}/rooms/{direct_id}/messages", headers=haA, json={"content": "یک پیامِ بی‌ربطِ دیگر"})

        # search finds it
        r = await c.get(f"{BASE}/rooms/{direct_id}/messages/search", headers=haA, params={"q": token})
        check(r.status_code == 200, f"search status ({r.status_code})")
        res = r.json()
        check(any(m["id"] == msg_id for m in res), "search finds the unique message")
        check(all(token in m["content"] for m in res), "all results contain the term")

        # no result for gibberish
        r = await c.get(f"{BASE}/rooms/{direct_id}/messages/search", headers=haA, params={"q": "xقندعسل۰۰۰"})
        check(r.status_code == 200 and r.json() == [], "no-match returns empty")

        # min length validation (1 char) → 422
        r = await c.get(f"{BASE}/rooms/{direct_id}/messages/search", headers=haA, params={"q": "x"})
        check(r.status_code == 422, f"min-length 1 rejected ({r.status_code})")

        # non-member blocked: B-only group, A searches → 403
        r = await c.post(f"{BASE}/groups", headers=haB, json={"name": "grp b only s", "member_earth_ids": []})
        bonly = r.json()["id"]
        r = await c.get(f"{BASE}/rooms/{bonly}/messages/search", headers=haA, params={"q": token})
        check(r.status_code == 403, f"non-member search blocked ({r.status_code})")

    async with engine.begin() as conn:
        await conn.execute(text("DELETE FROM messages WHERE room_id = :r"), {"r": bonly})
        await conn.execute(text("DELETE FROM room_members WHERE room_id = :r"), {"r": bonly})
        await conn.execute(text("DELETE FROM message_rooms WHERE id = :r"), {"r": bonly})

    print(f"\n==== PASS={PASS} FAIL={FAIL} ====")


if __name__ == "__main__":
    asyncio.run(main())
