from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.adapters.deepcode_adapter import DeepCodeAdapter
from app.config import settings
from app.routers import architectures_router, build_router
from app.services.architecture_store import ArchitectureStore
from app.services.build_project_store import BuildProjectStore


TEST_JWT_SECRET = "test-supabase-jwt-secret"
DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"


def auth_token(user_id: str = DEFAULT_USER_ID, email: str = "user@soul.test") -> str:
    return jwt.encode(
        {
            "sub": user_id,
            "email": email,
            "role": "authenticated",
            "exp": datetime.now(timezone.utc) + timedelta(hours=1),
        },
        TEST_JWT_SECRET,
        algorithm="HS256",
    )


def auth_headers(user_id: str = DEFAULT_USER_ID) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth_token(user_id)}"}


@pytest.fixture(autouse=True)
def isolated_security_environment(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", TEST_JWT_SECRET)
    monkeypatch.setattr(settings, "BUILD_DOWNLOAD_SIGNING_SECRET", "test-download-secret")
    monkeypatch.setattr(settings, "AGENT_BACKEND_SHARED_SECRET", "test-agent-secret")
    monkeypatch.setattr(settings, "LIVEKIT_API_KEY", "test-livekit-key")
    monkeypatch.setattr(settings, "LIVEKIT_API_SECRET", "test-livekit-secret")
    monkeypatch.setattr(settings, "LIVEKIT_URL", "wss://livekit.example.test")
    monkeypatch.setattr(
        build_router,
        "project_store",
        BuildProjectStore(trusted_root=str(tmp_path / "builds")),
    )
    monkeypatch.setattr(build_router, "deepcode_adapter", DeepCodeAdapter())
    monkeypatch.setattr(
        architectures_router,
        "architecture_store",
        ArchitectureStore(trusted_root=str(tmp_path / "architectures")),
    )
