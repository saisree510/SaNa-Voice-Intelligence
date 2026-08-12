import io
import shutil
import zipfile
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)
TRUSTED_ROOT = Path(settings.BUILD_STORAGE_ROOT)


def _workspace(name: str) -> str:
    target = TRUSTED_ROOT / name
    if target.exists():
        shutil.rmtree(target, ignore_errors=True)
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
    assert turn_data["events"][0]["event_type"] == "step_start"


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
    assert project_data["status"] == "plan_generated"
    assert "Awaiting explicit user approval" in project_data["plan_summary"]

    get_res = client.get(f"/v1/build/projects/{project_id}")
    assert get_res.status_code == 200
    assert get_res.json()["status"] == "plan_generated"

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["status"] == "completed"
    assert "Build execution completed" in approve_data["result_summary"]
    assert approve_data["workspace_path"] == workspace_path
    assert "project_spec.md" in approve_data["generated_files"]
    assert "main.py" in approve_data["generated_files"]
    assert approve_data["download_path"] == f"/v1/build/projects/{project_id}/download"
    assert "/v1/build/projects/" in approve_data["download_url"]
    assert "token=" in approve_data["download_url"]
    assert (Path(workspace_path) / "project_spec.md").exists()
    assert (Path(workspace_path) / "main.py").exists()
    assert len(approve_data["events"]) >= 2


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

    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["download_path"] == f"/v1/build/projects/{project_id}/download"

    download_res = client.get(f"/v1/build/projects/{project_id}/download")
    assert download_res.status_code == 200
    assert download_res.headers["content-type"].startswith("application/zip")
    assert f'{project_id}.zip' in download_res.headers["content-disposition"]

    archive = zipfile.ZipFile(io.BytesIO(download_res.content))
    assert sorted(archive.namelist()) == ["main.py", "project_spec.md"]

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
    assert sorted(signed_archive.namelist()) == ["main.py", "project_spec.md"]


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
