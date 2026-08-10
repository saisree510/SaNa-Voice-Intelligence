import os
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "SaNa Backend"
    ENVIRONMENT: str = "development"
    PORT: int = 8000
    
    # LiveKit configuration
    LIVEKIT_URL: str = "wss://sana-b8u74t7v.livekit.cloud"
    LIVEKIT_API_KEY: str = "APIbjA4T5tuugnd"
    LIVEKIT_API_SECRET: str = "wQ04yWjM1F2y98DkL3mP4v7N8qR1s2T3u4V5w6X7y8Z"
    
    # Supabase configuration
    SUPABASE_URL: str = "https://hpexmttbykelgkggjdvi.supabase.co"
    SUPABASE_ANON_KEY: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""
    SUPABASE_JWT_SECRET: Optional[str] = None
    
    # CORS origins
    CORS_ORIGINS: list[str] = ["*"]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
