"""سرویس Reputation — ثبت نظر و محاسبه‌ی امتیاز تجمیعی.

الگوریتم: امتیاز جدید = امتیاز قبلی × (1 - α) + امتیاز_نرمالیزه × α
  α = 0.1 برای کاربران قدیمی (review_count ≥ 20) | 0.3 برای جدیدتر
  امتیاز_نرمالیزه: rating (1–5) → (rating–1) × 250 (محدوده ۰–۱۰۰۰)
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.reputation.models import DOMAIN_TRUST, Review, ReputationScore
from app.modules.reputation.schemas import ReviewCreate

ALPHA_NEW = 0.3    # وزن برای کاربران با review_count < 20
ALPHA_OLD = 0.1    # وزن برای کاربران با review_count ≥ 20
THRESHOLD = 20


def _normalize_rating(rating: int) -> int:
    """تبدیل امتیاز ۱–۵ به بازه‌ی ۰–۱۰۰۰."""
    return (rating - 1) * 250


async def submit_review(
    db: AsyncSession, reviewer_earth_id: uuid.UUID, data: ReviewCreate
) -> Review:
    if reviewer_earth_id == data.reviewee_earth_id:
        raise ConflictError("به خودتان نمی‌توانید امتیاز بدهید.")

    # بررسی تکرار برای همان تراکنش
    dup = await db.execute(
        select(Review).where(
            Review.reviewer_earth_id == reviewer_earth_id,
            Review.transaction_ref == data.transaction_ref,
            Review.domain == data.domain,
        )
    )
    if dup.scalar_one_or_none() is not None:
        raise ConflictError("قبلاً برای این تراکنش امتیاز داده‌اید.")

    review = Review(
        reviewee_earth_id=data.reviewee_earth_id,
        reviewer_earth_id=reviewer_earth_id,
        domain=data.domain,
        transaction_ref=data.transaction_ref,
        rating=data.rating,
        comment=data.comment,
    )
    db.add(review)
    await db.flush()

    # به‌روزرسانی امتیاز تجمیعی (upsert)
    await _update_score(db, data.reviewee_earth_id, data.domain, data.rating)
    # امتیاز trust هم به‌روز می‌شود
    if data.domain != DOMAIN_TRUST:
        await _update_score(db, data.reviewee_earth_id, DOMAIN_TRUST, data.rating)

    await publisher.publish(
        db,
        DomainEvent(
            name="reputation.ReviewSubmitted",
            payload={
                "reviewee": str(data.reviewee_earth_id),
                "reviewer": str(reviewer_earth_id),
                "domain": data.domain,
                "rating": data.rating,
            },
        ),
    )
    return review


async def _update_score(
    db: AsyncSession, earth_id: uuid.UUID, domain: str, rating: int
) -> None:
    result = await db.execute(
        select(ReputationScore).where(
            ReputationScore.earth_id == earth_id,
            ReputationScore.domain == domain,
        )
    )
    score_row = result.scalar_one_or_none()

    normalized = _normalize_rating(rating)
    if score_row is None:
        db.add(ReputationScore(
            earth_id=earth_id,
            domain=domain,
            score=normalized,
            review_count=1,
        ))
    else:
        alpha = ALPHA_OLD if score_row.review_count >= THRESHOLD else ALPHA_NEW
        score_row.score = int(score_row.score * (1 - alpha) + normalized * alpha)
        score_row.review_count += 1
    await db.flush()


async def get_scores(db: AsyncSession, earth_id: uuid.UUID) -> list[ReputationScore]:
    result = await db.execute(
        select(ReputationScore).where(ReputationScore.earth_id == earth_id)
    )
    return list(result.scalars().all())


async def get_reviews(
    db: AsyncSession, earth_id: uuid.UUID, domain: str | None = None
) -> list[Review]:
    q = select(Review).where(Review.reviewee_earth_id == earth_id)
    if domain:
        q = q.where(Review.domain == domain)
    result = await db.execute(q.order_by(Review.created_at.desc()).limit(50))
    return list(result.scalars().all())
