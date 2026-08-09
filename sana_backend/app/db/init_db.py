"""Creates tables if they don't exist yet.

No migration framework (Alembic) for V1 per scope — `create_all` is
additive and safe to call on every startup (it never drops or alters
existing tables). Add Alembic when schema changes need to be tracked
across environments, not before.
"""

from .. import models  # noqa: F401  (populates Base's mapper registry)
from .session import Base, engine


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
