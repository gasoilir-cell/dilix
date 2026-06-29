"""سرویس KYC — ارسال درخواست، بررسی، تأیید/رد و به‌روزرسانیِ kyc_level."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.errors import ConflictError, NotFoundError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.identity.models import EarthIdentity
from app.modules.kyc.models import (
    STATUS_APPROVED,
    STATUS_IN_REVIEW,
    STATUS_PENDING,
    STATUS_REJECTED,
    KycRequest,
)
from app.modules.kyc.schemas import KycRequestCreate, KycReview


async def submit(
    db: AsyncSession, *, subject_earth_id: uuid.UUID, data: KycRequestCreate
) -> KycRequest:
    # بررسی: درخواستِ pending/in_review موازی نداشته باشد
    existing = await db.execute(
        select(KycRequest).where(
            KycRequest.subject_earth_id == subject_earth_id,
            KycRequest.status.in_([STATUS_PENDING, STATUS_IN_REVIEW]),
        )
    )
    if existing.scalars().first():
        raise ConflictError("درخواستِ KYC در حالِ بررسی وجود دارد.")

    req = KycRequest(
        subject_earth_id=subject_earth_id,
        requested_level=data.requested_level,
        documents=data.documents,
    )
    db.add(req)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="kyc.RequestSubmitted",
            payload={"request_id": str(req.id), "level": data.requested_level},
        ),
    )
    return req


async def review(
    db: AsyncSession,
    *,
    request_id: uuid.UUID,
    reviewer_earth_id: uuid.UUID,
    data: KycReview,
) -> KycRequest:
    req = await db.get(KycRequest, request_id)
    if req is None:
        raise NotFoundError("درخواستِ KYC یافت نشد.")
    if req.status not in (STATUS_PENDING, STATUS_IN_REVIEW):
        raise ConflictError(f"درخواست قابلِ بررسی نیست (وضعیت: {req.status}).")

    req.reviewer_earth_id = reviewer_earth_id
    req.reviewed_at = datetime.now(timezone.utc)
    req.note = data.note

    if data.approved:
        req.status = STATUS_APPROVED
        # ارتقایِ kyc_level روی EarthIdentity
        identity = await db.get(EarthIdentity, req.subject_earth_id)
        if identity and identity.kyc_level < req.requested_level:
            identity.kyc_level = req.requested_level
        event_name = "kyc.Approved"
    else:
        req.status = STATUS_REJECTED
        event_name = "kyc.Rejected"

    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name=event_name,
            payload={
                "request_id": str(req.id),
                "subject_earth_id": str(req.subject_earth_id),
                "level": req.requested_level,
            },
        ),
    )
    return req


async def my_requests(
    db: AsyncSession, subject_earth_id: uuid.UUID
) -> list[KycRequest]:
    result = await db.execute(
        select(KycRequest)
        .where(KycRequest.subject_earth_id == subject_earth_id)
        .order_by(KycRequest.created_at.desc())
    )
    return list(result.scalars().all())
