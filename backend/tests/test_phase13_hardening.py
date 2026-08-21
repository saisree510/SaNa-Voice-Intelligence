from pathlib import Path
from fastapi.testclient import TestClient
from app.main import app
from app.routers import build_router
from conftest import auth_headers

client = TestClient(app)
USER1 = "10000000-0000-0000-0000-000000000001"
USER2 = "20000000-0000-0000-0000-000000000002"


def _workspace(user_id: str, name: str) -> str:
    return str(Path(build_router.project_store.user_workspace_root(user_id)) / name)


def test_user_isolation_security():
    """Verify that build projects are strictly isolated per authenticated user."""
    # User 1 creates a build project
    headers_user1 = auth_headers(USER1)
    resp1 = client.post(
        "/v1/build/projects",
        json={
            "title": "User 1 Confidential Project",
            "specification": "Secrets and sensitive data",
            "workspace_path": _workspace(USER1, "user1_confidential_project"),
        },
        headers=headers_user1,
    )
    assert resp1.status_code == 200
    proj1_id = resp1.json()["project_id"]
    session_id = resp1.json()["session_id"]

    # User 2 attempts to fetch User 1's project -> Expect 403 Forbidden
    headers_user2 = auth_headers(USER2)
    resp2_list = client.get("/v1/build/projects", headers=headers_user2)
    assert resp2_list.status_code == 200
    assert all(item["project_id"] != proj1_id for item in resp2_list.json())

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

    # User 2 attempts to request a signed download link for User 1's project -> Expect 403 Forbidden
    resp2_download_link = client.get(f"/v1/build/projects/{proj1_id}/download-link", headers=headers_user2)
    assert resp2_download_link.status_code == 403

    resp2_session = client.get(f"/v1/build/sessions/{session_id}", headers=headers_user2)
    assert resp2_session.status_code == 403

    resp2_session_turn = client.post(
        f"/v1/build/sessions/{session_id}/turns",
        json={"prompt": "Bypass project ownership"},
        headers=headers_user2,
    )
    assert resp2_session_turn.status_code == 403


def test_unauthenticated_access_denied():
    """Verify unauthenticated requests without bearer tokens are rejected."""
    resp = client.get("/v1/build/projects")
    assert resp.status_code == 401


def test_project_approval_execution_flow():
    """Verify end-to-end plan creation -> explicit approval -> DeepCode execution flow."""
    headers = auth_headers(USER1)
    create_resp = client.post(
        "/v1/build/projects",
        json={
            "title": "Phase 13 Test Calculator App",
            "specification": "Create a calculator module",
            "workspace_path": _workspace(USER1, "phase13_test_calculator_app"),
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
    project = client.get(f"/v1/build/projects/{proj_id}", headers=headers).json()
    assert all(item["user_id"] == USER1 for item in project["generated_files"])
    assert all(item["project_id"] == proj_id for item in project["generated_files"])
    assert all(turn["user_id"] == USER1 for turn in project["history"])
    assert all(
        event["user_id"] == USER1
        for turn in project["history"]
        for event in turn["events"]
    )
