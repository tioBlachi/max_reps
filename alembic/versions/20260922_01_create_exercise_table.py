"""Create the exercise table.

Revision ID: 20260922_01
Revises:
Create Date: 2026-09-22
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "20260922_01"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "exercise",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("instructions", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_exercise_name", "exercise", ["name"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_exercise_name", table_name="exercise")
    op.drop_table("exercise")
