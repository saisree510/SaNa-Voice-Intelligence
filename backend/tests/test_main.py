import jwt
from fastapi.testclient import TestClient
from app.main import app

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
        json={"mode": "debate"}
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
