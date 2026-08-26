import io
from uuid import uuid4
import zipfile
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.routers import build_router
from app.services.architecture_store import ArchitectureStore
from conftest import DEFAULT_USER_ID, auth_headers

client = TestClient(app)
client.headers.update(auth_headers())


def _workspace(name: str, user_id: str = DEFAULT_USER_ID) -> str:
    target = Path(build_router.project_store.user_workspace_root(user_id)) / name
    return str(target)


def test_create_and_get_build_session():
    workspace_path = _workspace("sample_app")
    response = client.post(
        "/v1/build/sessions",
        json={
            "workspace_path": workspace_path,
            "model": "google/gemma-4-31b-it",
            "access_level": "full-access",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "session_id" in data
    session_id = data["session_id"]
    assert data["status"] == "idle"

    get_res = client.get(f"/v1/build/sessions/{session_id}")
    assert get_res.status_code == 200
    get_data = get_res.json()
    assert get_data["session_id"] == session_id
    assert get_data["workspace_path"] == workspace_path


def test_run_build_turn():
    workspace_path = _workspace("sample_app_turn")
    create_res = client.post(
        "/v1/build/sessions",
        json={"workspace_path": workspace_path},
    )
    session_id = create_res.json()["session_id"]

    turn_res = client.post(
        f"/v1/build/sessions/{session_id}/turns",
        json={"prompt": "Scaffold a modern landing page"},
    )
    assert turn_res.status_code == 200
    turn_data = turn_res.json()
    assert turn_data["session_id"] == session_id
    assert turn_data["status"] == "completed"
    assert len(turn_data["events"]) >= 2
    assert turn_data["events"][0]["event_type"] in ("step_start", "start")


def test_internal_agent_headers_attribute_project_to_supplied_user():
    agent_user_id = "user-from-agent-123"
    workspace_path = _workspace("agent_scoped_project", agent_user_id)
    headers = {
        "X-Sana-Agent-User-Id": agent_user_id,
        "X-Sana-Agent-Secret": settings.AGENT_BACKEND_SHARED_SECRET or settings.LIVEKIT_API_SECRET,
    }
    create_res = TestClient(app).post(
        "/v1/build/projects",
        json={
            "title": "Agent Scoped Build",
            "specification": "Build for the connected authenticated user",
            "workspace_path": workspace_path,
        },
        headers=headers,
    )
    assert create_res.status_code == 200
    assert create_res.json()["user_id"] == "user-from-agent-123"


def test_internal_agent_headers_normalize_prefixed_uuid_user_id():
    raw_user_id = "11111111-1111-1111-1111-111111111111"
    workspace_path = _workspace("agent_prefixed_uuid_project", raw_user_id)
    headers = {
        "X-Sana-Agent-User-Id": f"user-{raw_user_id}",
        "X-Sana-Agent-Secret": settings.AGENT_BACKEND_SHARED_SECRET or settings.LIVEKIT_API_SECRET,
    }
    create_res = TestClient(app).post(
        "/v1/build/projects",
        json={
            "title": "Agent UUID Build",
            "specification": "Build for a UUID-backed authenticated user",
            "workspace_path": workspace_path,
        },
        headers=headers,
    )
    assert create_res.status_code == 200
    assert create_res.json()["user_id"] == raw_user_id


def test_raw_user_can_list_and_access_prefixed_legacy_projects():
    from app.models.deepcode_models import BuildProjectModel
    from app.routers.build_router import project_store

    raw_user_id = "22222222-2222-2222-2222-222222222222"
    prefixed_user_id = f"user-{raw_user_id}"
    workspace_path = Path(_workspace("prefixed_legacy_project", raw_user_id))
    workspace_path.mkdir(parents=True, exist_ok=True)
    (workspace_path / "main.py").write_text("print('legacy project')\n", encoding="utf-8")

    project = BuildProjectModel(
        project_id="proj-prefixed-legacy",
        user_id=prefixed_user_id,
        title="Prefixed Legacy Project",
        specification="Legacy prefixed user id test",
        workspace_path=str(workspace_path),
        status="completed",
        plan_summary="Ready",
        session_id="dc-sess-prefixed-legacy",
        created_at="2026-08-13T01:00:00",
        updated_at="2026-08-13T01:00:01",
    )
    project_store.upsert_project(project)

    headers = auth_headers(raw_user_id)
    list_res = client.get("/v1/build/projects", headers=headers)
    get_res = client.get("/v1/build/projects/proj-prefixed-legacy", headers=headers)
    link_res = client.get("/v1/build/projects/proj-prefixed-legacy/download-link", headers=headers)

    assert list_res.status_code == 200
    assert any(item["project_id"] == "proj-prefixed-legacy" for item in list_res.json())
    assert get_res.status_code == 200
    assert get_res.json()["user_id"] == prefixed_user_id
    assert link_res.status_code == 200


def test_create_project_and_approval_gate():
    workspace_path = _workspace("dashboard_app")
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Flutter Realtime Dashboard",
            "specification": "Build a dark mode voice control analytics dashboard",
            "workspace_path": workspace_path,
        },
    )
    assert create_res.status_code == 200
    project_data = create_res.json()
    project_id = project_data["project_id"]
    architecture_id = project_data["architecture_id"]
    assert project_data["status"] == "plan_generated"
    assert "Awaiting explicit user approval" in project_data["plan_summary"]
    assert architecture_id

    architecture_res = client.get(f"/v1/architectures/{architecture_id}")
    assert architecture_res.status_code == 200
    architecture_data = architecture_res.json()
    assert architecture_data["project_id"] == project_id
    blueprint = architecture_data["current_blueprint"]
    assert blueprint["project_id"] == project_id
    assert [component["name"] for component in blueprint["components"][:2]] == ["Project UI", "Application Logic"]
    assert blueprint["connections"][0]["source_id"] == "frontend"
    assert blueprint["connections"][0]["target_id"] == "logic"

    get_res = client.get(f"/v1/build/projects/{project_id}")
    assert get_res.status_code == 200
    assert get_res.json()["status"] == "plan_generated"
    assert get_res.json()["architecture_id"] == architecture_id

    confirm_res = client.post(f"/v1/build/projects/{project_id}/prototype-scaffold/confirm")
    assert confirm_res.status_code == 200

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["status"] == "completed"
    assert "Build execution completed" in approve_data["result_summary"]
    assert approve_data["workspace_path"] == workspace_path
    generated_files = approve_data["generated_files"]
    assert "project_spec.md" in generated_files
    assert "README.md" in generated_files
    assert "main.py" in generated_files
    assert "pyproject.toml" in generated_files
    assert ".gitignore" in generated_files
    assert any(path.startswith("src/") for path in generated_files)
    assert any(path.startswith("tests/") for path in generated_files)
    assert approve_data["download_path"] == f"/v1/build/projects/{project_id}/download"
    assert "/v1/build/projects/" in approve_data["download_url"]
    assert "token=" in approve_data["download_url"]
    assert (Path(workspace_path) / "project_spec.md").exists()
    assert (Path(workspace_path) / "README.md").exists()
    assert (Path(workspace_path) / "main.py").exists()
    assert (Path(workspace_path) / "pyproject.toml").exists()
    assert any(p.is_dir() and p.name == "src" for p in Path(workspace_path).iterdir())
    assert any(p.is_dir() and p.name == "tests" for p in Path(workspace_path).iterdir())
    assert len(approve_data["events"]) >= 2


def test_project_is_persisted_before_linked_architecture(monkeypatch):
    class OrderingArchitectureStore(ArchitectureStore):
        def create_architecture(self, record):
            assert build_router.project_store.get_project(record.project_id) is not None
            return super().create_architecture(record)

    store = OrderingArchitectureStore(trusted_root=_workspace("architecture_order"))
    monkeypatch.setattr(build_router, "architecture_store", store)

    response = client.post(
        "/v1/build/projects",
        json={
            "title": "Architecture ordering check",
            "specification": "Build a simple web application",
            "workspace_path": _workspace("architecture_order_project"),
        },
    )

    assert response.status_code == 200
    assert response.json()["architecture_id"]


def test_project_links_existing_draft_architecture():
    architecture_id = "arch-existing-draft"
    create_architecture = client.post(
        "/v1/architectures",
        json={
            "title": "Existing Draft",
            "blueprint": {
                "architecture_id": architecture_id,
                "version": 1,
                "status": "draft",
                "components": [],
                "connections": [],
            },
        },
    )
    assert create_architecture.status_code == 200

    project_response = client.post(
        "/v1/build/projects",
        json={
            "title": "Linked Draft Project",
            "specification": "Build a simple calculator",
            "workspace_path": _workspace("linked_draft_project"),
            "architecture_id": architecture_id,
        },
    )

    assert project_response.status_code == 200
    project = project_response.json()
    assert project["architecture_id"] == architecture_id
    architecture = client.get(f"/v1/architectures/{architecture_id}").json()
    assert architecture["project_id"] == project["project_id"]
    assert architecture["current_blueprint"]["project_id"] == project["project_id"]


def test_approval_blocked_until_scaffold_confirmed():
    workspace_path = _workspace("scaffold_consent_gate")
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Scaffold Consent Gate",
            "specification": "Build something while DeepCode is unavailable",
            "workspace_path": workspace_path,
        },
    )
    assert create_res.status_code == 200
    project_id = create_res.json()["project_id"]

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 409
    assert "prototype-scaffold/confirm" in approve_res.json()["detail"]

    get_res = client.get(f"/v1/build/projects/{project_id}")
    assert get_res.json()["status"] == "plan_generated"
    assert get_res.json()["scaffold_confirmed"] is False

    confirm_res = client.post(f"/v1/build/projects/{project_id}/prototype-scaffold/confirm")
    assert confirm_res.status_code == 200
    assert confirm_res.json()["scaffold_confirmed"] is True

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    assert approve_res.json()["status"] == "completed"


def test_approve_latest_pending_project():
    first_workspace = _workspace("latest_pending_one")
    second_workspace = _workspace("latest_pending_two")

    first_res = client.post(
        "/v1/build/projects",
        json={
            "title": "First Pending Build",
            "specification": "Build the first draft",
            "workspace_path": first_workspace,
        },
    )
    assert first_res.status_code == 200

    second_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Second Pending Build",
            "specification": "Build the second draft",
            "workspace_path": second_workspace,
        },
    )
    assert second_res.status_code == 200
    latest_project_id = second_res.json()["project_id"]

    confirm_res = client.post(f"/v1/build/projects/{latest_project_id}/prototype-scaffold/confirm")
    assert confirm_res.status_code == 200

    approve_res = client.post("/v1/build/projects/approve-latest")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["project_id"] == latest_project_id
    assert approve_data["workspace_path"] == second_workspace
    assert "main.py" in approve_data["generated_files"]
    assert (Path(second_workspace) / "main.py").exists()


def test_download_project_archive():
    workspace_path = _workspace("downloadable_build")
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Downloadable Build",
            "specification": "Build a downloadable sample",
            "workspace_path": workspace_path,
        },
    )
    assert create_res.status_code == 200
    project_id = create_res.json()["project_id"]

    confirm_res = client.post(f"/v1/build/projects/{project_id}/prototype-scaffold/confirm")
    assert confirm_res.status_code == 200

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["download_path"] == f"/v1/build/projects/{project_id}/download"

    download_res = client.get(f"/v1/build/projects/{project_id}/download")
    assert download_res.status_code == 200
    assert download_res.headers["content-type"].startswith("application/zip")
    assert f'{project_id}.zip' in download_res.headers["content-disposition"]

    archive = zipfile.ZipFile(io.BytesIO(download_res.content))
    archive_names = sorted(archive.namelist())
    assert "project_spec.md" in archive_names
    assert "README.md" in archive_names
    assert "main.py" in archive_names
    assert "pyproject.toml" in archive_names
    assert ".gitignore" in archive_names
    assert any(name.startswith("src/") for name in archive_names)
    assert any(name.startswith("tests/") for name in archive_names)

    link_res = client.get(f"/v1/build/projects/{project_id}/download-link")
    assert link_res.status_code == 200
    link_data = link_res.json()
    assert link_data["project_id"] == project_id
    assert "/v1/build/projects/" in link_data["download_url"]
    assert "token=" in link_data["download_url"]

    signed_download_url = link_data["download_url"].replace("http://testserver", "")
    signed_download_res = client.get(signed_download_url)
    assert signed_download_res.status_code == 200
    signed_archive = zipfile.ZipFile(io.BytesIO(signed_download_res.content))
    signed_archive_names = sorted(signed_archive.namelist())
    assert "project_spec.md" in signed_archive_names
    assert "README.md" in signed_archive_names
    assert "main.py" in signed_archive_names
    assert any(name.startswith("src/") for name in signed_archive_names)
    assert any(name.startswith("tests/") for name in signed_archive_names)


def test_persistent_project_continuation_and_history():
    workspace_path = _workspace("cli_assistant")
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Persistent AI Assistant",
            "specification": "Build a CLI assistant",
            "workspace_path": workspace_path,
        },
    )
    project_id = create_res.json()["project_id"]
    client.post(f"/v1/build/projects/{project_id}/prototype-scaffold/confirm")
    client.post(f"/v1/build/projects/{project_id}/approve")

    list_res = client.get("/v1/build/projects")
    assert list_res.status_code == 200
    projects = list_res.json()
    assert any(p["project_id"] == project_id for p in projects)

    inc_res = client.post(
        f"/v1/build/projects/{project_id}/turns",
        json={"prompt": "Add voice logging module to CLI assistant"},
    )
    assert inc_res.status_code == 200
    assert inc_res.json()["status"] == "completed"

    hist_res = client.get(f"/v1/build/projects/{project_id}/history")
    assert hist_res.status_code == 200
    history = hist_res.json()
    assert len(history) >= 2
    assert history[-1]["prompt"] == "Add voice logging module to CLI assistant"


def test_authenticated_user_cannot_claim_another_users_projects():
    workspace_path = _workspace("legacy_claim_project")
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Legacy Claim Project",
            "specification": "Build a project created before auth wiring",
            "workspace_path": workspace_path,
        },
    )
    assert create_res.status_code == 200
    project_id = create_res.json()["project_id"]
    client.post(f"/v1/build/projects/{project_id}/prototype-scaffold/confirm")
    client.post(f"/v1/build/projects/{project_id}/approve")

    claimed_user_id = f"user-claimed-{uuid4().hex[:8]}"
    headers = auth_headers(claimed_user_id)
    list_res = client.get("/v1/build/projects", headers=headers)

    assert list_res.status_code == 200
    projects = list_res.json()
    assert all(p["project_id"] != project_id for p in projects)

    get_res = client.get(f"/v1/build/projects/{project_id}", headers=headers)
    assert get_res.status_code == 403
