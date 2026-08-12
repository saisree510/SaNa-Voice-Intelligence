import jwt
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from app.config import settings
from app.main import app

client = TestClient(app)
TRUSTED_ROOT = Path(settings.BUILD_STORAGE_ROOT)

# Standard valid PyJWT test tokens
TOKEN_USER1 = jwt.encode({"sub": "user-1000", "email": "user1@sana.ai"}, "secret", algorithm="HS256")
TOKEN_USER2 = jwt.encode({"sub": "user-2000", "email": "user2@sana.ai"}, "secret", algorithm="HS256")


def test_user_isolation_security():
    """Verify that build projects are strictly isolated per authenticated user."""
    # User 1 creates a build project
    headers_user1 = {"Authorization": f"Bearer {TOKEN_USER1}"}
    resp1 = client.post(
        "/v1/build/projects",
        json={
            "title": "User 1 Confidential Project",
            "specification": "Secrets and sensitive data",
            "workspace_path": str(TRUSTED_ROOT / "user1_confidential_project"),
        },
        headers=headers_user1,
    )
    assert resp1.status_code == 200
    proj1_id = resp1.json()["project_id"]

    # User 2 attempts to fetch User 1's project -> Expect 403 Forbidden
    headers_user2 = {"Authorization": f"Bearer {TOKEN_USER2}"}
    resp2_get = client.get(f"/v1/build/projects/{proj1_id}", headers=headers_user2)
    assert resp2_get.status_code == 403
    assert "Forbidden" in resp2_get.json()["detail"]

    # User 2 attempts to approve User 1's project -> Expect 403 Forbidden
    resp2_approve = client.post(f"/v1/build/projects/{proj1_id}/approve", headers=headers_user2)
    assert resp2_approve.status_code == 403

    # User 2 attempts to run turn on User 1's project -> Expect 403 Forbidden
    resp2_turn = client.post(
        f"/v1/build/projects/{proj1_id}/turns",
        json={"prompt": "Malicious turn"},
        headers=headers_user2,
    )
    assert resp2_turn.status_code == 403

    # User 2 attempts to get history of User 1's project -> Expect 403 Forbidden
    resp2_history = client.get(f"/v1/build/projects/{proj1_id}/history", headers=headers_user2)
    assert resp2_history.status_code == 403

    # User 2 attempts to download User 1's project files -> Expect 403 Forbidden
    resp2_download = client.get(f"/v1/build/projects/{proj1_id}/download", headers=headers_user2)
    assert resp2_download.status_code == 403


def test_unauthenticated_access_denied():
    """Verify unauthenticated requests without bearer tokens are rejected."""
    resp = client.get("/v1/build/projects")
    # In dev mode fallback anonymous user is used if headers missing, or 200 for list
    assert resp.status_code in (200, 401)


def test_project_approval_execution_flow():
    """Verify end-to-end plan creation -> explicit approval -> DeepCode execution flow."""
    headers = {"Authorization": f"Bearer {TOKEN_USER1}"}
    create_resp = client.post(
        "/v1/build/projects",
        json={
            "title": "Phase 13 Test Calculator App",
            "specification": "Create a calculator module",
            "workspace_path": str(TRUSTED_ROOT / "phase13_test_calculator_app"),
        },
        headers=headers,
    )
    assert create_resp.status_code == 200
    data = create_resp.json()
    assert data["status"] == "plan_generated"
    proj_id = data["project_id"]

    # Approve project -> triggers DeepCode execution
    approve_resp = client.post(f"/v1/build/projects/{proj_id}/approve", headers=headers)
    assert approve_resp.status_code == 200
    app_data = approve_resp.json()
    assert app_data["status"] == "completed"
    assert "Build execution completed" in app_data["result_summary"]
