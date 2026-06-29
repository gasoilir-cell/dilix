"""تست‌های واحدِ بدون نیاز به دیتابیس: Earth ID، امنیت، و موتور مجوز."""
from __future__ import annotations

import uuid


from dilix_shared.earth_id import EarthId


def test_earth_id_new_is_unique() -> None:
    a, b = EarthId.new(), EarthId.new()
    assert a != b
    assert isinstance(a.value, uuid.UUID)


def test_earth_id_parse_roundtrip() -> None:
    eid = EarthId.new()
    assert EarthId.parse(str(eid)) == eid


def test_password_hash_and_verify() -> None:
    from app.core.security import hash_password, verify_password

    hashed = hash_password("Secret123!")
    assert hashed != "Secret123!"
    assert verify_password("Secret123!", hashed)
    assert not verify_password("wrong", hashed)


def test_access_token_roundtrip() -> None:
    from app.core.security import create_access_token, decode_token

    eid = str(EarthId.new())
    payload = decode_token(create_access_token(eid))
    assert payload["sub"] == eid
    assert payload["type"] == "access"


def test_policy_rbac_denies_unknown_action() -> None:
    from app.modules.authorization.policy import AccessRequest, is_allowed

    req = AccessRequest(
        subject_role="individual",
        subject_kyc_level=2,
        subject_earth_id="x",
        action="freight.release_escrow",
    )
    assert is_allowed(req) is False


def test_policy_abac_requires_kyc_and_ownership() -> None:
    from app.modules.authorization.policy import AccessRequest, is_allowed

    # صاحب بار، سطح KYC کافی، مالک منبع → مجاز
    ok = AccessRequest(
        subject_role="cargo_owner",
        subject_kyc_level=2,
        subject_earth_id="owner-1",
        action="freight.release_escrow",
        resource_owner_id="owner-1",
        required_kyc_level=2,
    )
    assert is_allowed(ok) is True

    # همان اقدام اما کاربرِ غیرمالک → رد (جلوگیری از IDOR)
    not_owner = AccessRequest(
        subject_role="cargo_owner",
        subject_kyc_level=2,
        subject_earth_id="owner-2",
        action="freight.release_escrow",
        resource_owner_id="owner-1",
        required_kyc_level=2,
    )
    assert is_allowed(not_owner) is False


def test_global_admin_bypasses() -> None:
    from app.modules.authorization.policy import AccessRequest, is_allowed

    req = AccessRequest(
        subject_role="global_admin",
        subject_kyc_level=0,
        subject_earth_id="admin",
        action="anything.at.all",
    )
    assert is_allowed(req) is True
