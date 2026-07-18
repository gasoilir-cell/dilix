"""تستِ واحدِ موتورِ تصمیمِ مجوز (PDP) — ماژولِ authorization پشتیبان است و
endpoint ندارد، اما تابعِ خالصِ `is_allowed` منطقِ RBAC + ABAC دارد.
"""
from __future__ import annotations

from app.modules.authorization.policy import AccessRequest, is_allowed


def _req(**kw) -> AccessRequest:
    base = dict(
        subject_role="individual",
        subject_kyc_level=0,
        subject_earth_id="u1",
        action="identity.read_self",
    )
    base.update(kw)
    return AccessRequest(**base)


def test_rbac_allows_role_permission() -> None:
    assert is_allowed(_req(action="identity.read_self")) is True


def test_rbac_denies_unknown_action() -> None:
    assert is_allowed(_req(action="freight.post")) is False


def test_rbac_denies_unknown_role() -> None:
    assert is_allowed(_req(subject_role="ghost")) is False


def test_global_admin_wildcard_allows_any_action() -> None:
    assert is_allowed(_req(subject_role="global_admin", action="anything.at_all")) is True


def test_abac_blocks_insufficient_kyc_level() -> None:
    assert is_allowed(_req(required_kyc_level=2, subject_kyc_level=1)) is False


def test_abac_allows_sufficient_kyc_level() -> None:
    assert is_allowed(_req(required_kyc_level=2, subject_kyc_level=2)) is True


def test_abac_blocks_foreign_resource_owner() -> None:
    # مالکِ منبع فردِ دیگری است و نقش wildcard ندارد → رد (ضدِ IDOR).
    assert is_allowed(_req(subject_earth_id="u1", resource_owner_id="u2")) is False


def test_abac_allows_own_resource() -> None:
    assert is_allowed(_req(subject_earth_id="u1", resource_owner_id="u1")) is True


def test_global_admin_bypasses_ownership_check() -> None:
    assert is_allowed(
        _req(subject_role="global_admin", action="x", subject_earth_id="u1", resource_owner_id="u2")
    ) is True
