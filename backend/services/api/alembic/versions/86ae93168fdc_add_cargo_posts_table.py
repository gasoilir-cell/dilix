"""add_cargo_posts_table

Revision ID: 86ae93168fdc
Revises: 0001
Create Date: 2026-07-02 20:15:52.818443

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '86ae93168fdc'
down_revision: Union[str, None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE TYPE cargo_status_enum AS ENUM ('open', 'in_progress', 'delivered', 'cancelled')")
    op.create_table('cargo_posts',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('ref', sa.String(20), nullable=False, unique=True, index=True),
        sa.Column('owner_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('origin', sa.String(500), nullable=False),
        sa.Column('origin_lat', sa.Float(), nullable=True),
        sa.Column('origin_lng', sa.Float(), nullable=True),
        sa.Column('destination', sa.String(500), nullable=False),
        sa.Column('dest_lat', sa.Float(), nullable=True),
        sa.Column('dest_lng', sa.Float(), nullable=True),
        sa.Column('cargo_type', sa.String(100), nullable=False),
        sa.Column('weight_kg', sa.Float(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('price', sa.BigInteger(), nullable=False),
        sa.Column('status', sa.Enum('open', 'in_progress', 'delivered', 'cancelled', name='cargo_status_enum', create_type=False), nullable=False, server_default='open'),
        sa.Column('driver_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('pickup_date', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()')),
    )
    op.create_index('ix_cargo_posts_status', 'cargo_posts', ['status'])


def downgrade() -> None:
    op.drop_table('cargo_posts')
    op.execute('DROP TYPE cargo_status_enum')
