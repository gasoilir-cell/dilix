"""
Dilix — اعتبار (Reputation): امتیازِ حوزه‌ای + نظرِ پس از معامله

    GET  /api/v1/reputation/scores/{earth_id}   امتیازِ کاربر به‌تفکیکِ حوزه
    GET  /api/v1/reputation/reviews/{earth_id}  نظرهای دریافتیِ کاربر
    POST /api/v1/reputation/reviews             ثبتِ نظر

سه تصمیمی که ساختار را تعیین کرد:

۱) **هر نظر به یک مرجعِ معامله گره خورده و `(نظردهنده، حوزه، مرجع)` یکتاست.**
   بدونِ این ایندکس، یک نفر می‌توانست صد بار به رقیبش ۱ بدهد و امتیازِ او را
   نابود کند. یکتایی در سطحِ **دیتابیس** است، نه `if` پایتونی که دو درخواستِ
   هم‌زمان از آن رد می‌شوند.

۲) **امتیازِ تجمیعی از میانگینِ واقعیِ نظرها بازمحاسبه می‌شود، نه با جمعِ
   افزایشی.** جمعِ افزایشی با یک خطا برای همیشه منحرف می‌ماند؛ بازمحاسبه
   خودترمیم است.

۳) **کاربرِ بدونِ نظر امتیازِ پایهٔ ۵۰۰ (از ۱۰۰۰) می‌گیرد، نه صفر.** صفر یعنی
   «بد»، در حالی که واقعیت «هنوز نامعلوم» است؛ کاربرِ تازه نباید با برچسبِ
   بدترین‌ممکن شروع کند.
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    Column, DateTime, ForeignKey, Index, Integer, String, Text, func, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User

router = APIRouter(prefix="/reputation", tags=["Reputation"])

DOMAINS = {
    "logistics": "حمل‌ونقل",
    "financial": "مالی",
    "social":    "اجتماعی",
    "trust":     "اعتمادِ کلی",
}
BASE_SCORE = 500      # امتیازِ پایه از ۱۰۰۰ برای کاربرِ بدونِ نظر


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل ───────────────────────────────────────────────────────────────────────
class Review(Base):
    """نظرِ ثبت‌شده پس از یک معاملهٔ واقعی."""
    __tablename__ = "reputation_reviews"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    reviewee_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    reviewer_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                         nullable=False)
    domain = Column(String(32), nullable=False)
    transaction_ref = Column(String(128), nullable=False, default="")
    rating = Column(Integer, nullable=False)          # ۱..۵
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_reputation_review", "reviewer_id", "domain", "transaction_ref",
              unique=True),
    )


# ── Schemas ───────────────────────────────────────────────────────────────────
class ScoreOut(BaseModel):
    earth_id:     str
    domain:       str
    domain_label: str
    score:        int
    review_count: int


class ReviewOut(BaseModel):
    id:                 str
    reviewee_earth_id:  str
    reviewer_earth_id:  str
    domain:             str
    transaction_ref:    str
    rating:             int
    comment:            Optional[str]
    created_at:         datetime


class ReviewCreate(BaseModel):
    reviewee_earth_id: str
    domain:            str = Field("trust")
    transaction_ref:   str = Field("", max_length=128)
    rating:            int = Field(..., ge=1, le=5)
    comment:           Optional[str] = Field(None, max_length=2000)


# ── Helpers ───────────────────────────────────────────────────────────────────
async def _user_by_earth_id(db: AsyncSession, earth_id: str) -> User:
    u = (await db.execute(
        select(User).where(User.earth_id == earth_id)
    )).scalar_one_or_none()
    if u is None:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    return u


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("/scores/{earth_id}", response_model=List[ScoreOut])
async def scores(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """امتیازِ هر حوزه از میانگینِ واقعیِ نظرهای همان حوزه بازمحاسبه می‌شود."""
    u = await _user_by_earth_id(db, earth_id)
    rows = (await db.execute(
        select(Review.domain, func.avg(Review.rating), func.count(Review.id))
        .where(Review.reviewee_id == u.id)
        .group_by(Review.domain)
    )).all()
    agg = {d: (float(a or 0), int(c or 0)) for d, a, c in rows}

    out: List[ScoreOut] = []
    for code, label in DOMAINS.items():
        avg, cnt = agg.get(code, (0.0, 0))
        # میانگینِ ۱..۵ → مقیاسِ ۰..۱۰۰۰؛ نبودِ نظر یعنی امتیازِ پایه.
        score = int(round(avg / 5 * 1000)) if cnt else BASE_SCORE
        out.append(ScoreOut(
            earth_id=u.earth_id, domain=code, domain_label=label,
            score=score, review_count=cnt,
        ))
    return out


@router.get("/reviews/{earth_id}", response_model=List[ReviewOut])
async def reviews(
    earth_id: str,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    u = await _user_by_earth_id(db, earth_id)
    rows = (await db.execute(
        select(Review).where(Review.reviewee_id == u.id)
        .order_by(Review.created_at.desc()).limit(max(1, min(limit, 200)))
    )).scalars().all()
    if not rows:
        return []

    # نامِ نظردهنده‌ها در یک کوئری، نه یکی در هر حلقه (N+1).
    ids = {r.reviewer_id for r in rows} | {u.id}
    names = {
        uid: eid for uid, eid in (await db.execute(
            select(User.id, User.earth_id).where(User.id.in_(ids))
        )).all()
    }
    return [
        ReviewOut(
            id=str(r.id), reviewee_earth_id=names.get(r.reviewee_id, ""),
            reviewer_earth_id=names.get(r.reviewer_id, ""),
            domain=r.domain, transaction_ref=r.transaction_ref or "",
            rating=r.rating, comment=r.comment, created_at=r.created_at,
        )
        for r in rows
    ]


@router.post("/reviews", response_model=ReviewOut, status_code=201)
async def create_review(
    body: ReviewCreate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if body.domain not in DOMAINS:
        raise HTTPException(status_code=400, detail="حوزهٔ نامعتبر")
    target = await _user_by_earth_id(db, body.reviewee_earth_id)
    if target.id == me.id:
        raise HTTPException(status_code=400, detail="به خودتان نمی‌توانید امتیاز بدهید")

    r = Review(
        reviewee_id=target.id, reviewer_id=me.id, domain=body.domain,
        transaction_ref=(body.transaction_ref or "").strip(),
        rating=body.rating, comment=body.comment,
    )
    db.add(r)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="برای این معامله قبلاً نظر داده‌اید")
    await db.refresh(r)
    return ReviewOut(
        id=str(r.id), reviewee_earth_id=target.earth_id, reviewer_earth_id=me.earth_id,
        domain=r.domain, transaction_ref=r.transaction_ref or "", rating=r.rating,
        comment=r.comment, created_at=r.created_at,
    )
