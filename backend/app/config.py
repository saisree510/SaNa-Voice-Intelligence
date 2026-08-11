import os
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "SaNa Backend"
    ENVIRONMENT: str = "development"
    PORT: int = 8000
    
    # LiveKit configuration
    LIVEKIT_URL: str = "wss://sana-jjdz0xfv.livekit.cloud"
    LIVEKIT_API_KEY: str = "APIQnhXyFWJBjJW"
    LIVEKIT_API_SECRET: str = "XLh2uGFGCF1S3xJ6VeS0IlqFm2IdoaZ7lfR9w7o7YQH"
    
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
