"""ارکستراسیونِ بیمه — quote → issue → claim (ADR-02/ADR-07).

Dilix بیمه‌گر نیست: adapterِ بیمه‌گر کار را انجام می‌دهد و Dilix حالت و
external_ref را ثبت و رویداد منتشر می‌کند (از طریقِ Outbox). هر گذار با ماشینِ
حالتِ خالص اعتبارسنجی می‌شود.
"""
from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from dilix_shared.adapter import AdapterError
from dilix_shared.errors import ConflictError, ForbiddenError, NotFoundError, ProviderError
from dilix_shared.events import DomainEvent

from app.core.events import publisher
from app.modules.insurance.adapters import insurance_registry
from app.modules.insurance.models import (
    STATUS_CLAIMED,
    STATUS_ISSUED,
    InsurancePolicy,
)
from app.modules.insurance.ports import QuoteRequest
from app.modules.insurance.schemas import ClaimCreate, QuoteCreate
from app.modules.insurance.state import can_transition


def _to_domain(exc: AdapterError) -> ProviderError:
    return ProviderError(exc.detail)


async def _set_status(
    db: AsyncSession, policy: InsurancePolicy, target: str, event_name: str, **extra
) -> None:
    if not can_transition(policy.status, target):
        raise ConflictError(f"گذارِ نامعتبر: {policy.status} → {target}")
    policy.status = target
    await db.flush()
    payload = {
        "policy_id": str(policy.id),
        "status": target,
        "external_ref": policy.external_ref,
    }
    payload.update(extra)
    await publisher.publish(db, DomainEvent(name=event_name, payload=payload))


async def create_quote(
    db: AsyncSession, *, holder_earth_id: uuid.UUID, data: QuoteCreate
) -> InsurancePolicy:
    """دریافتِ نرخ و ثبتِ بیمه‌نامه در حالتِ quoted (هنوز صادر نشده)."""
    adapter = insurance_registry.get(data.provider_code)
    try:
        quote = await adapter.quote(
            QuoteRequest(
                product_code=data.product_code,
                holder_ref=str(holder_earth_id),
                coverage_minor=data.coverage_minor,
                currency=data.currency.upper(),
                attributes=data.attributes,
            )
        )
    except AdapterError as exc:
        raise _to_domain(exc) from exc

    policy = InsurancePolicy(
        holder_earth_id=holder_earth_id,
        provider_code=data.provider_code,
        product_code=data.product_code,
        coverage_minor=data.coverage_minor,
        premium_minor=quote.premium_minor,
        currency=data.currency.upper(),
        quote_ref=quote.quote_ref,
    )
    db.add(policy)
    await db.flush()
    await publisher.publish(
        db,
        DomainEvent(
            name="insurance.QuoteCreated",
            payload={"policy_id": str(policy.id), "premium_minor": quote.premium_minor},
        ),
    )
    return policy


async def _load_owned(
    db: AsyncSession, policy_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> InsurancePolicy:
    policy = await db.get(InsurancePolicy, policy_id)
    if policy is None:
        raise NotFoundError("بیمه‌نامه یافت نشد.")
    if policy.holder_earth_id != actor_earth_id:
        raise ForbiddenError("اجازه‌ی این عملیات را ندارید.")
    return policy


async def issue(
    db: AsyncSession, policy_id: uuid.UUID, actor_earth_id: uuid.UUID
) -> InsurancePolicy:
    policy = await _load_owned(db, policy_id, actor_earth_id)
    adapter = insurance_registry.get(policy.provider_code)
    try:
        result = await adapter.issue(policy.quote_ref or "")
    except AdapterError as exc:
        raise _to_domain(exc) from exc
    policy.external_ref = result.external_ref
    await _set_status(db, policy, STATUS_ISSUED, "insurance.PolicyIssued")
    return policy


async def claim(
    db: AsyncSession, policy_id: uuid.UUID, actor_earth_id: uuid.UUID, data: ClaimCreate
) -> InsurancePolicy:
    policy = await _load_owned(db, policy_id, actor_earth_id)
    adapter = insurance_registry.get(policy.provider_code)
    try:
        result = await adapter.claim(policy.external_ref or "", data.amount_minor, data.reason)
    except AdapterError as exc:
        raise _to_domain(exc) from exc
    await _set_status(
        db, policy, STATUS_CLAIMED, "insurance.ClaimRegistered", claim_ref=result.claim_ref
    )
    return policy
