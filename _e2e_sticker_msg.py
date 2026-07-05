import asyncio, io, sys
import httpx
from sqlalchemy import select, text
from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token
from app.models.user import User

BASE = "http://localhost:8000/api/v1"
_fail = 0
def check(cond, label):
    global _fail
    print(("OK  " if cond else "XX  ") + label)
    if not cond: _fail += 1

PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000d49444154789c6360000002000154a24f620000000049454e44ae426082"
)

async def main():
    async with AsyncSessionLocal() as db:
        us = (await db.execute(select(User).limit(2))).scalars().all()
        u1, u2 = us[0], us[1]
        t1 = create_access_token({"sub": str(u1.id)})
        e2 = u2.earth_id
    h1 = {"Authorization": f"Bearer {t1}"}
    pack_id = st_id = room_id = msg_id = None
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.post(f"{BASE}/stickers/packs", headers=h1, json={"title":"msg-test","is_public":False})
        pack_id = r.json()["id"]
        r = await c.post(f"{BASE}/stickers/packs/{pack_id}/stickers", headers=h1,
                         data={"emoji_tag":"🔥"}, files={"file":("s.png", io.BytesIO(PNG),"image/png")})
        st_id = r.json()["id"]
        # open direct room with user2
        r = await c.post(f"{BASE}/messages/rooms", headers=h1, json={"earth_id": e2})
        check(r.status_code in (200,201), f"open room ({r.status_code})")
        room_id = r.json()["id"]
        # send sticker
        r = await c.post(f"{BASE}/messages/rooms/{room_id}/sticker", headers=h1, json={"sticker_id": st_id})
        check(r.status_code==201, f"send sticker ({r.status_code})")
        j = r.json()
        msg_id = j["id"]
        check(j.get("sticker_id")==st_id, "message carries sticker_id")
        check(j.get("media_url","").startswith("/uploads/stickers/"), "message media_url = sticker url")
        # read back history
        r = await c.get(f"{BASE}/messages/rooms/{room_id}/messages", headers=h1)
        found = next((m for m in r.json() if m["id"]==msg_id), None)
        check(found is not None and found.get("sticker_id")==st_id, "history preserves sticker_id")
        # explore: get sticker -> pack_id
        r = await c.get(f"{BASE}/stickers/{st_id}", headers=h1)
        check(r.status_code==200 and r.json()["pack_id"]==pack_id, "explore resolves pack_id")
    async with AsyncSessionLocal() as db:
        await db.execute(text("delete from messages where id=:m"), {"m": msg_id})
        await db.execute(text("delete from stickers where pack_id=:p"), {"p": pack_id})
        await db.execute(text("delete from sticker_packs where id=:p"), {"p": pack_id})
        await db.commit()
    print("passed" if not _fail else f"failed {_fail}")
    sys.exit(1 if _fail else 0)

asyncio.run(main())
