import os
from typing import Optional
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


DEFAULT_BUILD_STORAGE_ROOT = str((Path(__file__).resolve().parents[2] / "drafts").resolve())


class Settings(BaseSettings):
    APP_NAME: str = "Soul Backend"
    ENVIRONMENT: str = "development"
    PORT: int = 8000

    # LiveKit configuration
    LIVEKIT_URL: str = ""
    LIVEKIT_API_KEY: str = ""
    LIVEKIT_API_SECRET: str = ""
    LIVEKIT_AGENT_NAME: str = "voice_agent"

    # Supabase configuration
    SUPABASE_URL: str = ""
    SUPABASE_ANON_KEY: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""
    SUPABASE_JWT_SECRET: Optional[str] = None

    # CORS origins
    CORS_ORIGINS: list[str] = ["*"]

    # Build Mode
    BUILD_MODE_ENABLED: bool = True
    BUILD_STORAGE_ROOT: str = os.getenv("BUILD_STORAGE_ROOT", DEFAULT_BUILD_STORAGE_ROOT)
    BUILD_DOWNLOAD_SIGNING_SECRET: Optional[str] = None
    AGENT_BACKEND_SHARED_SECRET: Optional[str] = (
        os.getenv("AGENT_BACKEND_SHARED_SECRET") or os.getenv("LIVEKIT_API_SECRET")
    )

    # DeepCode coding-agent settings
    DEEPCODE_ENABLED: bool = False
    DEEPCODE_BINARY_PATH: str = "deepcode"
    DEEPCODE_CONNECTION: str = "openrouter"   # deepcode provider name to use
    BUILD_RUN_TIMEOUT_SECONDS: int = 600      # 10 minutes per run
    BUILD_RUN_MAX_OUTPUT_BYTES: int = 2_000_000  # 2 MB stdout cap

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
