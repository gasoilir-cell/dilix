"""E2E: نظرسنجی (create + vote toggle + single/multiple + get_messages)."""
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

        # A یک نظرسنجی تک‌گزینه‌ای می‌سازد
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/poll", json={
            "question": "غذای محبوب؟", "options": ["پیتزا", "کباب", "سوشی"], "multiple": False,
        }, headers=ha)
        check(r.status_code == 201, f"create poll 201 ({r.status_code})")
        msg = r.json()
        check(msg.get("media_type") == "poll", "media_type=poll")
        poll = msg.get("poll")
        check(poll is not None, "poll object present")
        pid = poll["id"]
        check(len(poll["options"]) == 3, "3 options")
        check(poll["total_votes"] == 0, "0 votes initially")

        # اعتبارسنجی: کمتر از ۲ گزینه → 400
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/poll", json={
            "question": "؟", "options": ["تنها"],
        }, headers=ha)
        check(r.status_code == 422, f"one option 422 ({r.status_code})")

        # B به گزینهٔ ۰ رأی می‌دهد
        r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 0}, headers=hb)
        check(r.status_code == 200, f"vote 200 ({r.status_code})")
        p = r.json()
        check(p["options"][0]["votes"] == 1, "option0 votes=1")
        check(p["options"][0]["voted"] is True, "B voted option0")
        check(p["total_votes"] == 1, "total_votes=1")

        # B به گزینهٔ ۱ رأی می‌دهد → چون single است رأیِ قبلی جایگزین می‌شود
        r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 1}, headers=hb)
        p = r.json()
        check(p["options"][0]["votes"] == 0, "single: option0 back to 0")
        check(p["options"][1]["votes"] == 1, "single: option1 now 1")
        check(p["total_votes"] == 1, "single: still 1 voter")

        # A هم رأی می‌دهد → دو رأی‌دهنده
        r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 1}, headers=ha)
        p = r.json()
        check(p["options"][1]["votes"] == 2, "option1 votes=2")
        check(p["total_votes"] == 2, "total_votes=2")

        # B دوباره روی گزینهٔ ۱ می‌زند → toggle off
        r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 1}, headers=hb)
        p = r.json()
        check(p["options"][1]["voted"] is False, "B toggled off")
        check(p["options"][1]["votes"] == 1, "option1 back to 1")

        # نظرسنجیِ چند‌گزینه‌ای
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/poll", json={
            "question": "زبان‌ها؟", "options": ["پایتون", "راست", "گو"], "multiple": True,
        }, headers=ha)
        mpid = r.json()["poll"]["id"]
        await c.post(f"{BASE}/messages/polls/{mpid}/vote", json={"option_index": 0}, headers=hb)
        r = await c.post(f"{BASE}/messages/polls/{mpid}/vote", json={"option_index": 2}, headers=hb)
        p = r.json()
        check(p["options"][0]["votes"] == 1 and p["options"][2]["votes"] == 1, "multiple: two options selected")
        check(p["total_votes"] == 1, "multiple: still 1 voter")

        # get_messages نظرسنجی را با شمارش نشان می‌دهد
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=ha)
        rows = r.json()
        target = next((m for m in rows if m.get("poll") and m["poll"]["id"] == pid), None)
        check(target is not None, "get_messages includes poll")
        check(target["poll"]["options"][1]["votes"] == 1, "get_messages poll counts correct")

        # منفی: غیرعضو نمی‌تواند رأی دهد
        if third:
            hc = {"Authorization": f"Bearer {create_access_token({'sub': str(third.id)})}"}
            r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 0}, headers=hc)
            check(r.status_code == 403, f"non-member vote 403 ({r.status_code})")

        # منفی: گزینهٔ خارج از محدوده → 400
        r = await c.post(f"{BASE}/messages/polls/{pid}/vote", json={"option_index": 9}, headers=ha)
        check(r.status_code == 400, f"out-of-range option 400 ({r.status_code})")

        # منفی: نظرسنجیِ ناموجود → 404
        r = await c.post(f"{BASE}/messages/polls/00000000-0000-0000-0000-000000000000/vote", json={"option_index": 0}, headers=ha)
        check(r.status_code == 404, f"missing poll 404 ({r.status_code})")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())
