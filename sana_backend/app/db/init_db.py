"""Creates tables if they don't exist yet.

No migration framework (Alembic) for V1 per scope — `create_all` is
additive and safe to call on every startup (it never drops or alters
existing tables). Add Alembic when schema changes need to be tracked
across environments, not before.

`_add_missing_columns` is the one hand-rolled exception: `create_all`
truly never touches a table that already exists, even if the model
gained a new column since. Without it, `users.name` (added after real
local users already existed) would only ever exist for brand-new
databases, and every already-created sana.db would 500 on first read.
Written to still be dropped without regret once this project actually
needs Alembic — it's a stopgap, not infrastructure.
"""

from sqlalchemy import inspect, text

from .. import models  # noqa: F401  (populates Base's mapper registry)
from .session import Base, engine


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    _add_missing_columns()


def _add_missing_columns() -> None:
    inspector = inspect(engine)
    if 'users' not in inspector.get_table_names():
        return  # create_all() above just made it with the current schema already
    existing = {col['name'] for col in inspector.get_columns('users')}
    if 'name' not in existing:
        with engine.begin() as conn:
            conn.execute(text('ALTER TABLE users ADD COLUMN name VARCHAR(100)'))
