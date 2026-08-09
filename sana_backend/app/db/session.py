"""SQLAlchemy engine/session setup.

Works against SQLite (local dev/test, zero setup — see DATABASE_URL's
default in config.py) or PostgreSQL (set DATABASE_URL to a
postgresql+psycopg2:// URL) with no code changes — everything here is
plain, portable SQLAlchemy, nothing SQLite- or Postgres-specific.
"""

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from ..core.config import get_settings

settings = get_settings()

# check_same_thread is only meaningful for SQLite (FastAPI's threaded
# request handling would otherwise trip SQLite's default single-thread
# check); harmless to set unconditionally since Postgres's driver
# ignores it via connect_args filtering... actually psycopg2 doesn't
# accept this kwarg, so it's applied conditionally below.
connect_args = {'check_same_thread': False} if settings.database_url.startswith('sqlite') else {}

engine = create_engine(settings.database_url, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency — yields a request-scoped session, always closed after."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
