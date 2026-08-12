import os
import shutil
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
