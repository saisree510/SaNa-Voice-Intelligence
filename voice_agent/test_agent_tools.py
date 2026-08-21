import json
import os
import shutil
import urllib.request

import pytest
from src.agent import (
    approve_and_execute_build_project,
    build_backend_headers,
    create_build_project_plan,
    extract_participant_user_context,
)


@pytest.mark.asyncio
async def test_build_backend_headers_include_agent_user_context(monkeypatch):
    monkeypatch.setenv("AGENT_BACKEND_SHARED_SECRET", "shared-secret")

    headers = build_backend_headers(request_user_id="user-123", request_user_email="user@example.com")

    assert headers["Content-Type"] == "application/json"
    assert headers["X-Sana-Agent-User-Id"] == "user-123"
    assert headers["X-Sana-Agent-User-Email"] == "user@example.com"
    assert headers["X-Sana-Agent-Secret"] == "shared-secret"


def test_signed_participant_identity_overrides_editable_metadata():
    class Participant:
        identity = "user-real-user-id"
        metadata = json.dumps({"user_id": "another-users-id", "mode": "build"})

    context = extract_participant_user_context(Participant())

    assert context["user_id"] == "real-user-id"
    assert context["mode"] == "build"


@pytest.mark.asyncio
async def test_voice_agent_build_tools_offline_file_drafting(monkeypatch):
    monkeypatch.delenv("BACKEND_URL", raising=False)

    title = "Test Voice Analytics Dashboard"
    spec = "Build a real-time dashboard widget for voice analytics"

    plan_result = await create_build_project_plan(title, spec)
    assert "plan drafted" in plan_result.lower() or "project created" in plan_result.lower()
    assert "ID proj-" in plan_result

    exec_result = await approve_and_execute_build_project()
    assert "Build execution completed" in exec_result or "Execution result summary" in exec_result

    expected_draft_dir = os.path.abspath(r"C:\Users\saisr\Projects\SANA-LiveKit\drafts\test_voice_analytics_dashboard")
    if os.path.exists(expected_draft_dir):
        spec_file = os.path.join(expected_draft_dir, "project_spec.md")
        readme_file = os.path.join(expected_draft_dir, "README.md")
        code_file = os.path.join(expected_draft_dir, "main.py")
        pyproject_file = os.path.join(expected_draft_dir, "pyproject.toml")
        src_dir = os.path.join(expected_draft_dir, "src")
        tests_dir = os.path.join(expected_draft_dir, "tests")
        assert os.path.exists(spec_file), "project_spec.md missing from draft workspace"
        assert os.path.exists(readme_file), "README.md missing from draft workspace"
        assert os.path.exists(code_file), "main.py missing from draft workspace"
        assert os.path.exists(pyproject_file), "pyproject.toml missing from draft workspace"
        assert os.path.isdir(src_dir), "src directory missing from draft workspace"
        assert os.path.isdir(tests_dir), "tests directory missing from draft workspace"

        shutil.rmtree(expected_draft_dir, ignore_errors=True)


@pytest.mark.asyncio
async def test_voice_agent_remote_backend_omits_local_workspace(monkeypatch):
    monkeypatch.setenv("BACKEND_URL", "https://example.up.railway.app")

    captured = {}

    class DummyResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return json.dumps(
                {
                    "project_id": "proj-remote01",
                    "plan_summary": "Awaiting approval.",
                    "workspace_path": "/data/sana-builds/remote_project",
                }
            ).encode("utf-8")

    def fake_urlopen(request, timeout=0):
        captured["url"] = request.full_url
        captured["body"] = json.loads(request.data.decode("utf-8"))
        return DummyResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = await create_build_project_plan("Remote Project", "Build remotely")

    assert captured["url"].endswith("/v1/build/projects")
    assert "workspace_path" not in captured["body"]
    assert "/data/sana-builds/remote_project" in result


@pytest.mark.asyncio
async def test_voice_agent_approve_without_project_id_uses_latest_endpoint(monkeypatch):
    monkeypatch.setenv("BACKEND_URL", "https://example.up.railway.app")

    captured = {}

    class DummyResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return json.dumps(
                {
                    "project_id": "proj-remote01",
                    "result_summary": "Build execution completed for remote project.",
                    "workspace_path": "/data/sana-builds/remote_project",
                    "generated_files": [".gitignore", "README.md", "main.py", "project_spec.md", "pyproject.toml", "src/remote_project/app.py", "tests/test_app.py"],
                    "download_path": "/v1/build/projects/proj-remote01/download",
                    "download_url": "https://example.up.railway.app/v1/build/projects/proj-remote01/download/signed?token=test-token",
                }
            ).encode("utf-8")

    def fake_urlopen(request, timeout=0):
        captured["url"] = request.full_url
        return DummyResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = await approve_and_execute_build_project()

    assert captured["url"].endswith("/v1/build/projects/approve-latest")
    assert "Download: https://example.up.railway.app/v1/build/projects/proj-remote01/download/signed?token=test-token." in result
    assert "Files: .gitignore, README.md, main.py, project_spec.md, pyproject.toml, src/remote_project/app.py, tests/test_app.py." in result


async def test_voice_agent_approve_summary_includes_download_url(monkeypatch):
    monkeypatch.setenv("BACKEND_URL", "https://example.up.railway.app")

    class DummyResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return json.dumps(
                {
                    "result_summary": "Build execution completed for remote project.",
                    "workspace_path": "/data/sana-builds/remote_project",
                    "generated_files": [".gitignore", "README.md", "main.py", "project_spec.md", "pyproject.toml", "src/remote_project/app.py", "tests/test_app.py"],
                    "download_path": "/v1/build/projects/proj-remote01/download",
                    "download_url": "https://example.up.railway.app/v1/build/projects/proj-remote01/download/signed?token=test-token",
                }
            ).encode("utf-8")

    def fake_urlopen(request, timeout=0):
        return DummyResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = await approve_and_execute_build_project("proj-remote01")

    assert "Download: https://example.up.railway.app/v1/build/projects/proj-remote01/download/signed?token=test-token." in result
    assert "Files: .gitignore, README.md, main.py, project_spec.md, pyproject.toml, src/remote_project/app.py, tests/test_app.py." in result
