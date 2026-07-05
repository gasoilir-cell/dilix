"""E2E: سنجاقِ پیام (pin/unpin + list + is_pinned)."""
import asyncio
import httpx
from sqlalchemy import select

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
        third = (await db.execute(
            select(User).where(User.earth_id.notin_([A_EID, B_EID])).limit(1)
        )).scalar_one_or_none()

    ha = {"Authorization": f"Bearer {create_access_token({'sub': str(A.id)})}"}
    hb = {"Authorization": f"Bearer {create_access_token({'sub': str(B.id)})}"}

    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.post(f"{BASE}/messages/rooms", json={"earth_id": B_EID}, headers=ha)
        room_id = r.json()["id"]

        # A پیام می‌فرستد
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "پیامِ مهم برای سنجاق"}, headers=ha)
        check(r.status_code == 201, f"send message ({r.status_code})")
        msg = r.json()
        mid = msg["id"]
        check(msg.get("is_pinned") is False, "new message not pinned")

        # B آن را سنجاق می‌کند
        r = await c.post(f"{BASE}/messages/messages/{mid}/pin", headers=hb)
        check(r.status_code == 200, f"pin 200 ({r.status_code})")
        js = r.json()
        check(js.get("is_pinned") is True, "pin -> is_pinned true")
        check(js.get("pinned_count") == 1, f"pinned_count 1 ({js.get('pinned_count')})")

        # لیستِ پین‌ها شاملِ آن است
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/pins", headers=ha)
        pins = r.json()
        check(any(p["id"] == mid for p in pins), "pin appears in pins list")
        check(all(p["is_pinned"] for p in pins), "pins list items marked pinned")

        # get_messages نشان می‌دهد is_pinned=true
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=ha)
        rows = r.json()
        target = next((m for m in rows if m["id"] == mid), None)
        check(target is not None and target["is_pinned"] is True, "get_messages shows is_pinned")

        # toggle دوباره → برداشتنِ سنجاق
        r = await c.post(f"{BASE}/messages/messages/{mid}/pin", headers=ha)
        js = r.json()
        check(js.get("is_pinned") is False, "toggle -> unpinned")
        check(js.get("pinned_count") == 0, f"pinned_count 0 ({js.get('pinned_count')})")

        r = await c.get(f"{BASE}/messages/rooms/{room_id}/pins", headers=ha)
        check(all(p["id"] != mid for p in r.json()), "unpinned removed from pins list")

        # منفی: غیرعضو نمی‌تواند سنجاق کند
        if third:
            hc = {"Authorization": f"Bearer {create_access_token({'sub': str(third.id)})}"}
            r = await c.post(f"{BASE}/messages/messages/{mid}/pin", headers=hc)
            check(r.status_code == 403, f"non-member pin 403 ({r.status_code})")
            r = await c.get(f"{BASE}/messages/rooms/{room_id}/pins", headers=hc)
            check(r.status_code == 403, f"non-member pins 403 ({r.status_code})")

        # منفی: پیامِ ناموجود → 404
        r = await c.post(f"{BASE}/messages/messages/00000000-0000-0000-0000-000000000000/pin", headers=ha)
        check(r.status_code == 404, f"missing message 404 ({r.status_code})")

        # منفی: id نامعتبر → 400
        r = await c.post(f"{BASE}/messages/messages/not-a-uuid/pin", headers=ha)
        check(r.status_code == 400, f"invalid id 400 ({r.status_code})")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())
