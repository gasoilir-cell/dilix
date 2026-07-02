"""
Dilix — Freight Router
POST   /api/v1/freight/posts        ثبت بار جدید (صاحب بار / کارگزار)
GET    /api/v1/freight/posts        لیست بارهای موجود (راننده: open / صاحب بار: خودش)
GET    /api/v1/freight/posts/{id}   جزئیات یک بار
POST   /api/v1/freight/posts/{id}/take   راننده بار را می‌پذیرد
PUT    /api/v1/freight/posts/{id}/deliver  تأیید تحویل
DELETE /api/v1/freight/posts/{id}   لغو (فقط صاحب بار، وقتی open است)
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.freight import CargoPost

router = APIRouter(prefix="/freight", tags=["Freight"])


# ── Schemas ───────────────────────────────────────────────────
class CargoPostCreate(BaseModel):
    origin:      str       = Field(..., min_length=2, max_length=500)
    destination: str       = Field(..., min_length=2, max_length=500)
    origin_lat:  Optional[float] = None
    origin_lng:  Optional[float] = None
    dest_lat:    Optional[float] = None
    dest_lng:    Optional[float] = None
    cargo_type:  str       = Field(..., min_length=2, max_length=100)
    weight_kg:   float     = Field(..., gt=0)
    price:       int       = Field(..., gt=0)
    description: Optional[str] = None
    pickup_date: Optional[datetime] = None


class CargoPostOut(BaseModel):
    id:          str
    ref:         str
    owner_id:    str
    origin:      str
    destination: str
    origin_lat:  Optional[float]
    origin_lng:  Optional[float]
    dest_lat:    Optional[float]
    dest_lng:    Optional[float]
    cargo_type:  str
    weight_kg:   float
    price:       int
    description: Optional[str]
    status:      str
    driver_id:   Optional[str]
    pickup_date: Optional[datetime]
    created_at:  datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, obj: CargoPost) -> "CargoPostOut":
        return cls(
            id          = str(obj.id),
            ref         = obj.ref,
            owner_id    = str(obj.owner_id),
            origin      = obj.origin,
            destination = obj.destination,
            origin_lat  = obj.origin_lat,
            origin_lng  = obj.origin_lng,
            dest_lat    = obj.dest_lat,
            dest_lng    = obj.dest_lng,
            cargo_type  = obj.cargo_type,
            weight_kg   = obj.weight_kg,
            price       = obj.price,
            description = obj.description,
            status      = obj.status,
            driver_id   = str(obj.driver_id) if obj.driver_id else None,
            pickup_date = obj.pickup_date,
            created_at  = obj.created_at,
        )


def _gen_ref() -> str:
    """FRT-XXXXXXXX"""
    return "FRT-" + _uuid.uuid4().hex[:8].upper()


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/posts", response_model=CargoPostOut, status_code=status.HTTP_201_CREATED)
async def create_cargo_post(
    body: CargoPostCreate,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    """ثبت بار جدید — برای همه کاربران احرازهویت‌شده"""
    post = CargoPost(
        ref         = _gen_ref(),
        owner_id    = me.id,
        origin      = body.origin,
        destination = body.destination,
        origin_lat  = body.origin_lat,
        origin_lng  = body.origin_lng,
        dest_lat    = body.dest_lat,
        dest_lng    = body.dest_lng,
        cargo_type  = body.cargo_type,
        weight_kg   = body.weight_kg,
        price       = body.price,
        description = body.description,
        pickup_date = body.pickup_date,
        status      = "open",
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post)


@router.get("/posts", response_model=List[CargoPostOut])
async def list_cargo_posts(
    mine:  bool = Query(False, description="فقط بارهای خودم"),
    limit: int  = Query(50, le=200),
    db:    AsyncSession = Depends(get_db),
    me:    User         = Depends(get_current_user),
):
    """
    لیست بارها.
    - mine=false (پیش‌فرض): بارهای open برای رانندگان
    - mine=true: بارهای صاحب بار لاگین‌شده
    """
    if mine:
        q = select(CargoPost).where(CargoPost.owner_id == me.id)
    else:
        q = select(CargoPost).where(CargoPost.status == "open")

    q = q.order_by(CargoPost.created_at.desc()).limit(limit)
    result = await db.execute(q)
    posts  = result.scalars().all()
    return [CargoPostOut.from_orm(p) for p in posts]


@router.get("/posts/{post_id}", response_model=CargoPostOut)
async def get_cargo_post(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    return CargoPostOut.from_orm(post)


@router.post("/posts/{post_id}/take", response_model=CargoPostOut)
async def take_cargo(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """راننده بار را می‌پذیرد"""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.status != "open":
        raise HTTPException(status_code=400, detail="این بار دیگر در دسترس نیست")
    if post.owner_id == me.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید بار خود را بپذیرید")

    post.driver_id = me.id
    post.status    = "in_progress"
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post)


@router.put("/posts/{post_id}/deliver", response_model=CargoPostOut)
async def mark_delivered(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """تأیید تحویل (توسط صاحب بار یا راننده)"""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if me.id not in (post.owner_id, post.driver_id):
        raise HTTPException(status_code=403, detail="دسترسی ندارید")
    if post.status != "in_progress":
        raise HTTPException(status_code=400, detail="وضعیت نادرست")

    post.status = "delivered"
    await db.commit()
    await db.refresh(post)
    return CargoPostOut.from_orm(post)


@router.delete("/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_post(
    post_id: str,
    db:  AsyncSession = Depends(get_db),
    me:  User         = Depends(get_current_user),
):
    """لغو بار (فقط صاحب بار، وقتی open است)"""
    post = await db.get(CargoPost, _uuid.UUID(post_id))
    if not post:
        raise HTTPException(status_code=404, detail="بار پیدا نشد")
    if post.owner_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحب بار می‌تواند لغو کند")
    if post.status not in ("open",):
        raise HTTPException(status_code=400, detail="امکان لغو وجود ندارد")

    post.status = "cancelled"
    await db.commit()
