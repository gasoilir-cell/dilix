"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-06-21 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ─── enums — یک دستور در هر execute ─────────────────────────
    op.execute("CREATE TYPE user_role_enum AS ENUM ('user','driver','cargo_owner','freight_broker','insurance_agent','creator','admin','super_admin')")
    op.execute("CREATE TYPE user_tier_enum AS ENUM ('free','silver','gold','platinum')")
    op.execute("CREATE TYPE user_status_enum AS ENUM ('active','inactive','blocked','pending_verification')")
    op.execute("CREATE TYPE kyc_status_enum AS ENUM ('pending','approved','rejected','expired')")
    op.execute("CREATE TYPE wallet_tx_type_enum AS ENUM ('deposit','withdrawal','escrow_lock','escrow_release','transfer_in','transfer_out','refund','bonus','fee')")
    op.execute("CREATE TYPE wallet_tx_status_enum AS ENUM ('pending','completed','failed','reversed')")

    # ─── users ──────────────────────────────────────────────────
    op.execute("""
        CREATE TABLE users (
            id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
            earth_id        VARCHAR(20)  NOT NULL UNIQUE,
            phone           VARCHAR(20)  UNIQUE,
            email           VARCHAR(255) UNIQUE,
            full_name       VARCHAR(200),
            username        VARCHAR(50)  UNIQUE,
            avatar_url      TEXT,
            bio             TEXT,
            kyc_level       INTEGER      NOT NULL DEFAULT 0,
            kyc_status      kyc_status_enum DEFAULT 'pending',
            national_id     VARCHAR(255),
            date_of_birth   TIMESTAMPTZ,
            role            user_role_enum  NOT NULL DEFAULT 'user',
            tier            user_tier_enum  NOT NULL DEFAULT 'free',
            status          user_status_enum NOT NULL DEFAULT 'pending_verification',
            blocked_reason  TEXT,
            country_code    VARCHAR(3),
            locale          VARCHAR(10)  NOT NULL DEFAULT 'fa',
            timezone_name   VARCHAR(50)  NOT NULL DEFAULT 'Asia/Tehran',
            password_hash   VARCHAR(255),
            mfa_enabled     BOOLEAN      NOT NULL DEFAULT false,
            mfa_secret      VARCHAR(255),
            last_login_at   TIMESTAMPTZ,
            last_login_ip   VARCHAR(45),
            is_driver       BOOLEAN      NOT NULL DEFAULT false,
            driver_license_no     VARCHAR(50),
            driver_license_type   VARCHAR(10),
            driver_license_expiry TIMESTAMPTZ,
            trust_score     INTEGER      NOT NULL DEFAULT 0,
            avg_rating      INTEGER      NOT NULL DEFAULT 0,
            total_ratings   INTEGER      NOT NULL DEFAULT 0,
            total_trips     INTEGER      NOT NULL DEFAULT 0,
            completion_rate INTEGER      NOT NULL DEFAULT 100,
            privacy_on_map  BOOLEAN      NOT NULL DEFAULT false,
            metadata        JSONB        DEFAULT '{}',
            created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("CREATE INDEX ix_users_phone         ON users (phone)")
    op.execute("CREATE INDEX ix_users_earth_id      ON users (earth_id)")
    op.execute("CREATE INDEX ix_users_phone_status  ON users (phone, status)")
    op.execute("CREATE INDEX ix_users_role_status   ON users (role, status)")
    op.execute("CREATE INDEX ix_users_country_locale ON users (country_code, locale)")

    # ─── wallets ────────────────────────────────────────────────
    op.execute("""
        CREATE TABLE wallets (
            id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id           UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
            currency          VARCHAR(3)  NOT NULL DEFAULT 'IRR',
            balance_available BIGINT      NOT NULL DEFAULT 0,
            balance_escrow    BIGINT      NOT NULL DEFAULT 0,
            balance_bonus     BIGINT      NOT NULL DEFAULT 0,
            is_frozen         BOOLEAN     NOT NULL DEFAULT false,
            frozen_reason     TEXT,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
        )
    """)

    # ─── wallet_transactions ─────────────────────────────────────
    op.execute("""
        CREATE TABLE wallet_transactions (
            id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
            wallet_id      UUID         NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
            reference_id   VARCHAR(100),
            type           wallet_tx_type_enum   NOT NULL,
            status         wallet_tx_status_enum NOT NULL DEFAULT 'pending',
            amount         BIGINT       NOT NULL,
            balance_before BIGINT       NOT NULL,
            balance_after  BIGINT       NOT NULL,
            description    TEXT,
            metadata       JSONB,
            created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("CREATE INDEX ix_wallet_tx_created    ON wallet_transactions (wallet_id, created_at)")
    op.execute("CREATE INDEX ix_wallet_tx_type_status ON wallet_transactions (type, status)")
    op.execute("CREATE INDEX ix_wallet_tx_reference  ON wallet_transactions (reference_id)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS wallet_transactions")
    op.execute("DROP TABLE IF EXISTS wallets")
    op.execute("DROP TABLE IF EXISTS users")
    op.execute("DROP TYPE IF EXISTS wallet_tx_status_enum")
    op.execute("DROP TYPE IF EXISTS wallet_tx_type_enum")
    op.execute("DROP TYPE IF EXISTS kyc_status_enum")
    op.execute("DROP TYPE IF EXISTS user_status_enum")
    op.execute("DROP TYPE IF EXISTS user_tier_enum")
    op.execute("DROP TYPE IF EXISTS user_role_enum")
