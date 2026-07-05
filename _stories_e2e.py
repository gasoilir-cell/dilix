import asyncio, sys, struct, zlib
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

def tiny_png(color=(80, 120, 200)):
    # 2x2 solid PNG
    w = h = 2
    raw = b""
    for _ in range(h):
        raw += b"\x00" + bytes(color) * w
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

async def main():
    async with AsyncSessionLocal() as db:
        ra = await db.execute(select(User).where(User.earth_id == "DLX-OO39V4SY"))
        A = ra.scalar_one()
        rb = await db.execute(select(User).where(User.earth_id == "DLX-CSV157XM"))
        B = rb.scalar_one()
    ta = create_access_token({"sub": str(A.id)})
    tb = create_access_token({"sub": str(B.id)})
    ha = {"Authorization": f"Bearer {ta}"}
    hb = {"Authorization": f"Bearer {tb}"}
    png = tiny_png()

    async with httpx.AsyncClient(timeout=30) as c:
        # A creates a story
        r = await c.post(f"{BASE}/stories", headers=ha,
                         files={"file": ("s.png", png, "image/png")}, data={"caption": "سلام"})
        check(r.status_code == 201, f"A create story -> 201 (got {r.status_code})")
        sid = r.json().get("id")
        check(r.json().get("is_mine") is True, "story.is_mine True")
        check(r.json().get("media_type") == "image", "media_type image")

        # A feed contains own ring
        r = await c.get(f"{BASE}/stories/feed", headers=ha)
        rings = r.json()
        mine = [x for x in rings if x["earth_id"] == A.earth_id]
        check(bool(mine) and mine[0]["is_me"] is True, "A feed has own ring (is_me)")

        # ensure B follows A
        await c.post(f"{BASE}/social/follow", headers=hb, json={"earth_id": A.earth_id})

        # B feed shows A ring with unseen
        r = await c.get(f"{BASE}/stories/feed", headers=hb)
        aring = [x for x in r.json() if x["earth_id"] == A.earth_id]
        check(bool(aring), "B feed contains A ring")
        check(bool(aring) and aring[0]["has_unseen"] is True, "A ring has_unseen True (before view)")

        # B views the story
        r = await c.post(f"{BASE}/stories/{sid}/view", headers=hb)
        check(r.status_code == 204, f"B view -> 204 (got {r.status_code})")

        # idempotent second view
        r = await c.post(f"{BASE}/stories/{sid}/view", headers=hb)
        check(r.status_code == 204, "B view again -> 204 (idempotent)")

        # B feed now has_unseen False
        r = await c.get(f"{BASE}/stories/feed", headers=hb)
        aring = [x for x in r.json() if x["earth_id"] == A.earth_id]
        check(bool(aring) and aring[0]["has_unseen"] is False, "A ring has_unseen False (after view)")

        # A's user_stories: view_count == 1
        r = await c.get(f"{BASE}/stories/user/{A.earth_id}", headers=ha)
        st = r.json()
        check(len(st) >= 1 and st[0]["view_count"] == 1, f"view_count == 1 (got {st[0]['view_count'] if st else 'none'})")

        # B user_stories of A: viewed_by_me True
        r = await c.get(f"{BASE}/stories/user/{A.earth_id}", headers=hb)
        st = r.json()
        check(len(st) >= 1 and st[0]["viewed_by_me"] is True, "B sees viewed_by_me True")

        # A viewers list contains B
        r = await c.get(f"{BASE}/stories/{sid}/viewers", headers=ha)
        check(r.status_code == 200 and any(v["earth_id"] == B.earth_id for v in r.json()), "A viewers contains B")

        # B cannot see viewers (403)
        r = await c.get(f"{BASE}/stories/{sid}/viewers", headers=hb)
        check(r.status_code == 403, f"B viewers -> 403 (got {r.status_code})")

        # A deletes story
        r = await c.delete(f"{BASE}/stories/{sid}", headers=ha)
        check(r.status_code == 204, f"A delete -> 204 (got {r.status_code})")

        # gone from feed
        r = await c.get(f"{BASE}/stories/feed", headers=hb)
        aring = [x for x in r.json() if x["earth_id"] == A.earth_id]
        check(not aring, "A ring gone after delete")

    # cleanup: remove B->A follow + any leftover stories/views by A
    async with AsyncSessionLocal() as db:
        await db.execute(text("DELETE FROM story_views WHERE viewer_id = :b"), {"b": str(B.id)})
        await db.execute(text("DELETE FROM stories WHERE author_id = :a"), {"a": str(A.id)})
        await db.execute(text("DELETE FROM follows WHERE follower_id = :b AND following_id = :a"),
                         {"b": str(B.id), "a": str(A.id)})
        await db.commit()
    print("passed" if _fail == 0 else f"failed={_fail}")
    sys.exit(1 if _fail else 0)

asyncio.run(main())
