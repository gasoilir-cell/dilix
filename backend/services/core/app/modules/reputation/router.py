"""روتر Reputation (سند ۵: /v1/reputation/...)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import get_current_earth_id
from app.modules.reputation import service
from app.modules.reputation.schemas import ReviewCreate, ReviewOut, ScoreOut

router = APIRouter(prefix="/v1/reputation", tags=["reputation"])


@router.post("/reviews", response_model=ReviewOut, status_code=201)
async def submit_review(
    data: ReviewCreate,
    db: AsyncSession = Depends(get_session),
    earth_id: uuid.UUID = Depends(get_current_earth_id),
) -> ReviewOut:
    """ثبت امتیاز و نظر پس از تراکنش واقعی."""
    review = await service.submit_review(db, earth_id, data)
    return ReviewOut.model_validate(review, from_attributes=True)


@router.get("/scores/{earth_id}", response_model=list[ScoreOut])
async def get_scores(
    earth_id: uuid.UUID,
    db: AsyncSession = Depends(get_session),
    _: uuid.UUID = Depends(get_current_earth_id),
) -> list[ScoreOut]:
    """امتیازهای تجمیعی کاربر در همه‌ی دامنه‌ها."""
    scores = await service.get_scores(db, earth_id)
    return [
        ScoreOut(
            earth_id=s.earth_id,
            domain=s.domain,
            score=round(s.score / 10, 1),  # ۰–۱۰۰
            review_count=s.review_count,
        )
        for s in scores
    ]


@router.get("/reviews/{earth_id}", response_model=list[ReviewOut])
async def get_reviews(
    earth_id: uuid.UUID,
    domain: str | None = Query(default=None),
    db: AsyncSession = Depends(get_session),
    _: uuid.UUID = Depends(get_current_earth_id),
) -> list[ReviewOut]:
    """نظرات دریافت‌شده برای یک کاربر."""
    reviews = await service.get_reviews(db, earth_id, domain)
    return [ReviewOut.model_validate(r, from_attributes=True) for r in reviews]
