import jwt
from unittest.mock import patch
from fastapi.testclient import TestClient
from app.main import app
from conftest import auth_headers

client = TestClient(app)


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "service" in data


def test_system_status():
    response = client.get("/v1/status")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert "version" in data


def test_livekit_token_generation_unauthenticated_dev():
    response = client.post(
        "/v1/livekit/token",
        json={"mode": "debate"},
        headers=auth_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert "token" in data
    assert data["mode"] == "debate"
    assert "url" in data
    assert "participant_identity" in data

    claims = jwt.decode(
        data["token"],
        options={"verify_signature": False, "verify_aud": False},
        algorithms=["HS256"],
    )
    assert claims["video"]["canManageAgentSession"] is True
    assert claims["video"].get("agent") in (None, False)


def test_build_projects_rejects_signature_mismatch_token_in_development():
    token = jwt.encode({"sub": "user-1234", "email": "user@example.com"}, "different-secret", algorithm="HS256")
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.auth.auth_bearer.settings.SUPABASE_JWT_SECRET", "legacy-secret"), patch(
        "app.auth.auth_bearer.settings.ENVIRONMENT", "development"
    ):
        response = client.get("/v1/build/projects", headers=headers)

    assert response.status_code == 401


def test_build_projects_production_rejects_signature_mismatch_token():
    token = jwt.encode({"sub": "user-1234", "email": "user@example.com"}, "different-secret", algorithm="HS256")
    headers = {"Authorization": f"Bearer {token}"}

    with patch("app.auth.auth_bearer.settings.SUPABASE_JWT_SECRET", "legacy-secret"), patch(
        "app.auth.auth_bearer.settings.ENVIRONMENT", "production"
    ):
        response = client.get("/v1/build/projects", headers=headers)

    assert response.status_code == 401


def test_authenticated_routes_fallback_to_supabase_get_user_when_local_jwt_secret_mismatches():
    token = jwt.encode({"sub": "user-1234", "email": "user@example.com"}, "new-signing-key", algorithm="HS256")
    headers = {"Authorization": f"Bearer {token}"}

    class SupabaseUser:
        id = "user-1234"
        email = "user@example.com"
        user_metadata = {}

    class SupabaseAuth:
        @staticmethod
        def get_user(received_token):
            assert received_token == token
            return type("SupabaseResponse", (), {"user": SupabaseUser()})()

    class SupabaseClient:
        auth = SupabaseAuth()

    with patch("app.auth.auth_bearer.settings.SUPABASE_JWT_SECRET", "legacy-secret"), patch(
        "app.auth.auth_bearer.settings.SUPABASE_URL", "https://supabase.example.test"
    ), patch("app.auth.auth_bearer.settings.SUPABASE_ANON_KEY", "anon-key"), patch(
        "app.auth.auth_bearer.create_client", return_value=SupabaseClient()
    ):
        response = client.get("/v1/build/projects", headers=headers)

    assert response.status_code == 200


def test_protected_routes_reject_missing_session():
    assert client.get("/v1/build/projects").status_code == 401
    assert client.get("/v1/conversations").status_code == 401
    assert client.post("/v1/livekit/token", json={"mode": "general"}).status_code == 401
