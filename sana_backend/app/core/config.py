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

    # --- DeepCode (Build mode only — see app/services/deepcode_service.py) ---
    # Executable name/path for the `deepcode` CLI. Deliberately *not*
    # defaulted to a specific install location: this machine alone has
    # several different `deepcode` builds on PATH, and the one that
    # resolves first for a bare "deepcode" may not have the `exec`
    # subcommand at all (confirmed by testing). Set this to the full
    # path of your real DeepCode 2.0 install if the default doesn't work.
    deepcode_bin: str = 'deepcode'
    # Must match a connection already configured via `deepcode provider`
    # on this machine (e.g. `deepcode provider list`).
    deepcode_connection: str = 'local-ollama'
    deepcode_model: str = 'qwen2.5-coder:7b'
    # 'full-access' matches the project's own local, trusted-workspace
    # decision (spec's Build workspace rule) — DeepCode's sandbox/approval
    # prompts are for interactive use, not a headless backend call.
    deepcode_access: str = 'full-access'
    deepcode_trust: bool = True
    # Local LLM inference can be slow; generous default so a real task
    # isn't cut off mid-run.
    deepcode_timeout_seconds: int = 300

    # Root directory generated projects are built into — never sana_app
    # or sana_backend themselves (DeepCodeService refuses to start if
    # this ever resolves inside either). No default baked in as an
    # absolute path with a username in it; resolved relative to this
    # repo layout instead (sana-builds/ as a sibling of sana_app and
    # sana_backend), overridable via env for anyone whose layout differs.
    build_workspaces_root: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
