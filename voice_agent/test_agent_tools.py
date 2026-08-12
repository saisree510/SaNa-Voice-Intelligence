import json
import os
import shutil
import urllib.request

import pytest
from src.agent import create_build_project_plan, approve_and_execute_build_project


@pytest.mark.asyncio
async def test_voice_agent_build_tools_offline_file_drafting(monkeypatch):
    monkeypatch.delenv("BACKEND_URL", raising=False)

    title = "Test Voice Analytics Dashboard"
    spec = "Build a real-time dashboard widget for voice analytics"

    plan_result = await create_build_project_plan(title, spec)
    assert "plan drafted" in plan_result.lower() or "project created" in plan_result.lower()
    assert "ID proj-" in plan_result

    import re
    match = re.search(r"ID (proj-[a-zA-Z0-9-]+)", plan_result)
    assert match is not None, f"Failed to extract project ID from result: {plan_result}"
    project_id = match.group(1)

    exec_result = await approve_and_execute_build_project(project_id)
    assert "Build execution completed" in exec_result or "Execution result summary" in exec_result

    expected_draft_dir = os.path.abspath(r"C:\Users\saisr\Projects\SANA-LiveKit\drafts\test_voice_analytics_dashboard")
    if os.path.exists(expected_draft_dir):
        spec_file = os.path.join(expected_draft_dir, "project_spec.md")
        code_file = os.path.join(expected_draft_dir, "main.py")
        assert os.path.exists(spec_file), "project_spec.md missing from draft workspace"
        assert os.path.exists(code_file), "main.py missing from draft workspace"

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
                    "generated_files": ["main.py", "project_spec.md"],
                    "download_path": "/v1/build/projects/proj-remote01/download",
                }
            ).encode("utf-8")

    def fake_urlopen(request, timeout=0):
        return DummyResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = await approve_and_execute_build_project("proj-remote01")

    assert "Download: https://example.up.railway.app/v1/build/projects/proj-remote01/download." in result
    assert "Files: main.py, project_spec.md." in result
