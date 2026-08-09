"""Environment-backed settings, loaded once at import time.

Every part of the backend (FastAPI server, voice agent worker) imports
from here, so credentials are read from the environment in exactly one
place.
"""

from functools import lru_cache

from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict

# pydantic-settings (below) reads .env into its own Settings object,
# but never populates os.environ. livekit-agents' inference.LLM reads
# LIVEKIT_API_KEY etc. directly from os.environ, so without this it
# fails with "api_key is required" even though .env has it — confirmed
# by testing the real (non-mock) chat path. agent/voice_agent.py
# already did this for the same reason; the FastAPI app needs it too.
load_dotenv('.env')


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    # --- Voice (existing) ---
    livekit_url: str
    livekit_api_key: str
    livekit_api_secret: str
    port: int = 8000

    # --- Database ---
    # Defaults to a local SQLite file so the backend runs with zero
    # extra setup. Point this at a real Postgres instance for
    # production — e.g. postgresql+psycopg2://user:pass@host:5432/dbname
    # — no code changes needed, SQLAlchemy handles both.
    database_url: str = 'sqlite:///./sana.db'

    # --- Auth / JWT ---
    # No default — the app refuses to start without an explicit secret
    # (see database/session "fail loudly" philosophy applied to auth
    # too: a guessed/default secret would silently make every token
    # forgeable).
    jwt_secret_key: str
    jwt_algorithm: str = 'HS256'
    jwt_expire_minutes: int = 60 * 24 * 7  # 7 days

    # --- AI provider (text chat) ---
    # 'livekit' (default, reuses the LiveKit credentials above — no new
    # account needed) or 'mock' (canned responses, no network calls,
    # used by the test suite). See app/services/ai_service.py.
    ai_provider: str = 'livekit'
    ai_model: str = 'google/gemma-4-31b-it'


@lru_cache
def get_settings() -> Settings:
    return Settings()
