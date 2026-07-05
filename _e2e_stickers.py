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
        users = (await db.execute(select(User).limit(2))).scalars().all()
        u1, u2 = users[0], users[1]
        t1 = create_access_token({"sub": str(u1.id)})
        t2 = create_access_token({"sub": str(u2.id)})
    h1 = {"Authorization": f"Bearer {t1}"}
    h2 = {"Authorization": f"Bearer {t2}"}
    pack_id = None; st_id = None
    async with httpx.AsyncClient(timeout=30) as c:
        # create public pack (user1)
        r = await c.post(f"{BASE}/stickers/packs", headers=h1,
                         json={"title":"تست پک", "description":"e2e", "is_public":True})
        check(r.status_code==201, f"create pack ({r.status_code})")
        pack_id = r.json()["id"]
        # add sticker
        files = {"file": ("s.png", io.BytesIO(PNG), "image/png")}
        r = await c.post(f"{BASE}/stickers/packs/{pack_id}/stickers", headers=h1,
                         data={"emoji_tag":"😂"}, files=files)
        check(r.status_code==201, f"add sticker ({r.status_code})")
        st_id = r.json()["id"]
        check(r.json()["media_url"].startswith("/uploads/stickers/"), "sticker media_url")
        # mine
        r = await c.get(f"{BASE}/stickers/packs/mine", headers=h1)
        check(r.status_code==200 and any(p["id"]==pack_id and p["sticker_count"]==1 for p in r.json()), "mine lists pack w/ count")
        # public search by user2
        r = await c.get(f"{BASE}/stickers/packs/public", headers=h2, params={"q":"تست"})
        check(r.status_code==200 and any(p["id"]==pack_id for p in r.json()), "public search finds pack")
        found = next(p for p in r.json() if p["id"]==pack_id)
        check(found["is_mine"]==False and found["is_installed"]==False, "public pack flags for other user")
        # install by user2
        r = await c.post(f"{BASE}/stickers/packs/{pack_id}/install", headers=h2)
        check(r.status_code==200 and r.json()["installed"], "user2 install")
        r = await c.get(f"{BASE}/stickers/packs/installed", headers=h2)
        check(r.status_code==200 and any(p["id"]==pack_id for p in r.json()), "installed list")
        # detail w/ stickers (explore library)
        r = await c.get(f"{BASE}/stickers/packs/{pack_id}", headers=h2)
        check(r.status_code==200 and len(r.json()["stickers"])==1, "pack detail stickers")
        # star sticker (user2)
        r = await c.post(f"{BASE}/stickers/{st_id}/star", headers=h2)
        check(r.status_code==200 and r.json()["starred"], "star")
        r = await c.get(f"{BASE}/stickers/starred", headers=h2)
        check(r.status_code==200 and any(s["id"]==st_id for s in r.json()), "starred list")
        # unstar
        r = await c.delete(f"{BASE}/stickers/{st_id}/star", headers=h2)
        check(r.status_code==200 and not r.json()["starred"], "unstar")
        r = await c.get(f"{BASE}/stickers/starred", headers=h2)
        check(r.status_code==200 and not any(s["id"]==st_id for s in r.json()), "starred empty after unstar")
        # uninstall
        r = await c.delete(f"{BASE}/stickers/packs/{pack_id}/install", headers=h2)
        check(r.status_code==200 and not r.json()["installed"], "uninstall")
        # forbidden: user2 add sticker to user1 pack
        r = await c.post(f"{BASE}/stickers/packs/{pack_id}/stickers", headers=h2,
                         data={}, files={"file":("s.png", io.BytesIO(PNG), "image/png")})
        check(r.status_code==404, f"user2 cannot add to user1 pack ({r.status_code})")
    # cleanup
    async with AsyncSessionLocal() as db:
        await db.execute(text("delete from starred_stickers where sticker_id=:s"), {"s": st_id})
        await db.execute(text("delete from installed_packs where pack_id=:p"), {"p": pack_id})
        await db.execute(text("delete from stickers where pack_id=:p"), {"p": pack_id})
        await db.execute(text("delete from sticker_packs where id=:p"), {"p": pack_id})
        await db.commit()
    print("passed" if not _fail else f"failed {_fail}")
    sys.exit(1 if _fail else 0)

asyncio.run(main())
