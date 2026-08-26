from pathlib import Path
from fastapi.testclient import TestClient
from app.main import app
from app.routers import build_router
from app.models.build_models import BuildRunEvent
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

    # Explicit consent required before falling back to the Prototype Scaffold provider
    confirm_resp = client.post(
        f"/v1/build/projects/{proj_id}/prototype-scaffold/confirm", headers=headers
    )
    assert confirm_resp.status_code == 200
    assert confirm_resp.json()["scaffold_confirmed"] is True

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


def test_build_error_event_never_marks_existing_workspace_as_completed(monkeypatch):
    """A runtime error must not archive stale files as a successful DeepCode build."""
    class ErroringDeepCodeAdapter:
        provider_label = "deepcode"

        async def run(self, spec, run_id):
            Path(spec.workspace_path).mkdir(parents=True, exist_ok=True)
            (Path(spec.workspace_path) / "stale-scaffold.txt").write_text("old output")
            yield BuildRunEvent(
                run_id=run_id,
                sequence=1,
                event_type="error",
                message="DeepCode could not write the requested project.",
                provider=self.provider_label,
            )

        async def cancel(self, run_id):
            return None

    monkeypatch.setattr(build_router, "coding_adapter", ErroringDeepCodeAdapter())
    headers = auth_headers(USER1)
    create_resp = client.post(
        "/v1/build/projects",
        json={
            "title": "Failed runtime must not complete",
            "specification": "Create an app",
            "workspace_path": _workspace(USER1, "failed_runtime_must_not_complete"),
        },
        headers=headers,
    )
    project_id = create_resp.json()["project_id"]

    approve_resp = client.post(f"/v1/build/projects/{project_id}/approve", headers=headers)
    assert approve_resp.status_code == 500

    project = client.get(f"/v1/build/projects/{project_id}", headers=headers).json()
    assert project["status"] == "failed"
    assert project["generated_files"] == []
