"""E2E: forward message (named + anonymous + media) — Dilix messenger."""
import asyncio
import uuid as _uuid
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


def tiny_png():
    import base64
    return base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )


async def get_users():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.earth_id.in_(["DLX-OO39V4SY", "DLX-CSV157XM"])))
        rows = {u.earth_id: u for u in res.scalars().all()}
        return rows["DLX-OO39V4SY"], rows["DLX-CSV157XM"]


async def main():
    A, B = await get_users()
    haA = {"Authorization": f"Bearer {create_access_token({'sub': str(A.id)})}"}
    haB = {"Authorization": f"Bearer {create_access_token({'sub': str(B.id)})}"}
    b_name = B.full_name or B.username or B.earth_id

    created_rooms = []
    async with httpx.AsyncClient(timeout=20) as c:
        # 1) open/create direct room A<->B (A starts with B's earth_id)
        r = await c.post(f"{BASE}/rooms", headers=haA, json={"earth_id": B.earth_id})
        check(r.status_code in (200, 201), f"open direct room ({r.status_code})")
        direct_id = r.json()["id"]

        # 2) B sends a text message
        r = await c.post(f"{BASE}/rooms/{direct_id}/messages", headers=haB, json={"content": "پیام تست بازارسال"})
        check(r.status_code in (200, 201), f"B send text ({r.status_code})")
        text_msg_id = r.json()["id"]

        # 3) B sends a media message (image)
        files = {"file": ("t.png", tiny_png(), "image/png")}
        r = await c.post(f"{BASE}/rooms/{direct_id}/media", headers=haB, files=files)
        check(r.status_code in (200, 201), f"B send media ({r.status_code})")
        media_msg_id = r.json()["id"]

        # 4) A creates a target group
        r = await c.post(f"{BASE}/groups", headers=haA, json={"name": "گروه مقصد تست", "member_earth_ids": [B.earth_id]})
        check(r.status_code in (200, 201), f"A create group ({r.status_code})")
        group_id = r.json()["id"]
        created_rooms.append(group_id)

        # 5) A forwards B's text WITH name
        r = await c.post(f"{BASE}/messages/{text_msg_id}/forward", headers=haA, json={"room_id": group_id, "anonymous": False})
        check(r.status_code == 201, f"forward named ({r.status_code})")
        j = r.json()
        check(j.get("is_forwarded") is True, "named: is_forwarded=True")
        check(j.get("forwarded_from") == b_name, f"named: forwarded_from={j.get('forwarded_from')} (expect {b_name})")
        check(j.get("content") == "پیام تست بازارسال", "named: content copied")

        # 6) A forwards B's text ANONYMOUS
        r = await c.post(f"{BASE}/messages/{text_msg_id}/forward", headers=haA, json={"room_id": group_id, "anonymous": True})
        check(r.status_code == 201, f"forward anon ({r.status_code})")
        j = r.json()
        check(j.get("is_forwarded") is False, "anon: is_forwarded=False")
        check(j.get("forwarded_from") is None, "anon: forwarded_from=None")

        # 7) A forwards media
        r = await c.post(f"{BASE}/messages/{media_msg_id}/forward", headers=haA, json={"room_id": group_id, "anonymous": False})
        check(r.status_code == 201, f"forward media ({r.status_code})")
        j = r.json()
        check(bool(j.get("media_url")), "media: media_url copied")
        check(j.get("media_type") == "image", f"media: media_type={j.get('media_type')}")

        # 8) history of group has forwarded msgs
        r = await c.get(f"{BASE}/rooms/{group_id}/messages", headers=haA)
        check(r.status_code == 200, f"group history ({r.status_code})")
        hist = r.json() if isinstance(r.json(), list) else r.json().get("items", [])
        fwd = [m for m in hist if m.get("is_forwarded")]
        check(len(fwd) >= 2, f"history has forwarded msgs ({len(fwd)})")

        # 9) negative: forward to a room A is not member of (B-only group)
        r = await c.post(f"{BASE}/groups", headers=haB, json={"name": "گروه فقط B", "member_earth_ids": []})
        if r.status_code in (200, 201):
            bonly = r.json()["id"]
            created_rooms.append(bonly)
            r = await c.post(f"{BASE}/messages/{text_msg_id}/forward", headers=haA, json={"room_id": bonly, "anonymous": False})
            check(r.status_code in (403, 404), f"forward to non-member room blocked ({r.status_code})")

        # 10) negative: forward missing message
        r = await c.post(f"{BASE}/messages/{_uuid.uuid4()}/forward", headers=haA, json={"room_id": group_id, "anonymous": False})
        check(r.status_code == 404, f"forward missing msg 404 ({r.status_code})")

    # cleanup created rooms
    async with engine.begin() as conn:
        for rid in created_rooms:
            await conn.execute(text("DELETE FROM messages WHERE room_id = :r"), {"r": rid})
            await conn.execute(text("DELETE FROM room_members WHERE room_id = :r"), {"r": rid})
            await conn.execute(text("DELETE FROM message_rooms WHERE id = :r"), {"r": rid})

    print(f"\n==== PASS={PASS} FAIL={FAIL} ====")


if __name__ == "__main__":
    asyncio.run(main())
