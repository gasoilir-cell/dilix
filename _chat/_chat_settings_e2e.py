"""E2E: تنظیماتِ گفتگو — مسدودسازی + بی‌صداکردن + پاک‌کردنِ گفتگو."""
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

    ha = {"Authorization": f"Bearer {create_access_token({'sub': str(A.id)})}"}
    hb = {"Authorization": f"Bearer {create_access_token({'sub': str(B.id)})}"}

    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.post(f"{BASE}/messages/rooms", json={"earth_id": B_EID}, headers=ha)
        room_id = r.json()["id"]

        # پاک‌سازیِ وضعیتِ اولیه: اگر A قبلاً B را مسدود کرده باشد، رفع کن
        blocks = (await c.get(f"{BASE}/messages/blocks", headers=ha)).json()
        if B_EID in blocks:
            await c.post(f"{BASE}/messages/users/{B_EID}/block", headers=ha)

        # A یک پیام می‌فرستد (باید موفق باشد چون مسدودی وجود ندارد)
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "سلام قبل از مسدودی"}, headers=ha)
        check(r.status_code == 201, f"send before block 201 ({r.status_code})")

        # ── مسدودسازی ──
        r = await c.post(f"{BASE}/messages/users/{B_EID}/block", headers=ha)
        check(r.status_code == 200 and r.json()["blocked"] is True, f"block → blocked=true ({r.status_code})")

        # لیستِ مسدودشده‌ها شاملِ B است
        blocks = (await c.get(f"{BASE}/messages/blocks", headers=ha)).json()
        check(B_EID in blocks, "blocks list includes B")

        # A نمی‌تواند به B پیام دهد (مسدودی)
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "بعد از مسدودی"}, headers=ha)
        check(r.status_code == 403, f"A send while blocked 403 ({r.status_code})")

        # B هم نمی‌تواند به A پیام دهد (مسدودیِ دوطرفه در اتاق)
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "از طرفِ B"}, headers=hb)
        check(r.status_code == 403, f"B send while blocked 403 ({r.status_code})")

        # list_rooms برای A باید is_blocked=true بدهد
        rooms = (await c.get(f"{BASE}/messages/rooms", headers=ha)).json()
        room_a = next((x for x in rooms if x["id"] == room_id), None)
        check(room_a is not None and room_a.get("is_blocked") is True, "list_rooms is_blocked=true for A")

        # start_or_get_room هم is_blocked=true
        r = await c.post(f"{BASE}/messages/rooms", json={"earth_id": B_EID}, headers=ha)
        check(r.json().get("is_blocked") is True, "start_room is_blocked=true")

        # ── رفعِ مسدودی ──
        r = await c.post(f"{BASE}/messages/users/{B_EID}/block", headers=ha)
        check(r.status_code == 200 and r.json()["blocked"] is False, f"unblock → blocked=false ({r.status_code})")
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "بعد از رفعِ مسدودی"}, headers=ha)
        check(r.status_code == 201, f"send after unblock 201 ({r.status_code})")

        # منفی: مسدودکردنِ خود → 400
        r = await c.post(f"{BASE}/messages/users/{A_EID}/block", headers=ha)
        check(r.status_code == 400, f"self-block 400 ({r.status_code})")

        # منفی: کاربرِ ناموجود → 404
        r = await c.post(f"{BASE}/messages/users/DLX-NOEXIST9/block", headers=ha)
        check(r.status_code == 404, f"block unknown 404 ({r.status_code})")

        # ── بی‌صداکردن ──
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/mute", json={"muted": True, "duration_minutes": 480}, headers=ha)
        check(r.status_code == 200 and r.json()["muted"] is True, f"mute 480m → muted=true ({r.status_code})")
        check(r.json().get("muted_until") is not None, "mute has muted_until")

        rooms = (await c.get(f"{BASE}/messages/rooms", headers=ha)).json()
        room_a = next((x for x in rooms if x["id"] == room_id), None)
        check(room_a and room_a.get("is_muted") is True, "list_rooms is_muted=true")

        # بی‌صدای همیشگی (بدونِ duration)
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/mute", json={"muted": True}, headers=ha)
        check(r.status_code == 200 and r.json()["muted"] is True, "mute always → muted=true")

        # رفعِ بی‌صدا
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/mute", json={"muted": False}, headers=ha)
        check(r.status_code == 200 and r.json()["muted"] is False, "unmute → muted=false")
        rooms = (await c.get(f"{BASE}/messages/rooms", headers=ha)).json()
        room_a = next((x for x in rooms if x["id"] == room_id), None)
        check(room_a and room_a.get("is_muted") is False, "list_rooms is_muted=false after unmute")

        # ── پاک‌کردنِ گفتگو ──
        # A چند پیام دارد؛ ببینیم قبل از پاک، پیام هست
        before = (await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=ha)).json()
        check(len(before) > 0, "messages exist before clear")

        r = await c.post(f"{BASE}/messages/rooms/{room_id}/clear", headers=ha)
        check(r.status_code == 200 and r.json()["ok"] is True, f"clear 200 ({r.status_code})")

        # A دیگر پیامِ قدیمی نمی‌بیند
        after_a = (await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=ha)).json()
        check(len(after_a) == 0, f"A sees 0 messages after clear ({len(after_a)})")

        # B همچنان پیام‌ها را می‌بیند (پاک فقط یک‌طرفه است)
        after_b = (await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=hb)).json()
        check(len(after_b) > 0, f"B still sees messages after A clear ({len(after_b)})")

        # پیامِ جدیدِ بعد از پاک برای A دیده می‌شود
        await c.post(f"{BASE}/messages/rooms/{room_id}/messages", json={"content": "پیامِ بعد از پاک"}, headers=hb)
        after2 = (await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=ha)).json()
        check(len(after2) == 1, f"A sees only new message after clear ({len(after2)})")

        # منفی: mute/clear روی اتاقِ نامعتبر
        r = await c.post(f"{BASE}/messages/rooms/not-a-uuid/mute", json={"muted": True}, headers=ha)
        check(r.status_code == 400, f"mute invalid room 400 ({r.status_code})")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())
