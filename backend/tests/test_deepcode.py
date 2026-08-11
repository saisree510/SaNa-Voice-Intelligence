from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_create_and_get_build_session():
    # 1. Create build session
    response = client.post(
        "/v1/build/sessions",
        json={
            "workspace_path": "c:/Users/saisr/Projects/sample_app",
            "model": "google/gemma-4-31b-it",
            "access_level": "full-access"
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert "session_id" in data
    session_id = data["session_id"]
    assert data["status"] == "idle"

    # 2. Get build session
    get_res = client.get(f"/v1/build/sessions/{session_id}")
    assert get_res.status_code == 200
    get_data = get_res.json()
    assert get_data["session_id"] == session_id
    assert get_data["workspace_path"] == "c:/Users/saisr/Projects/sample_app"


def test_run_build_turn():
    # 1. Create session
    create_res = client.post(
        "/v1/build/sessions",
        json={"workspace_path": "c:/Users/saisr/Projects/sample_app"}
    )
    session_id = create_res.json()["session_id"]

    # 2. Run turn
    turn_res = client.post(
        f"/v1/build/sessions/{session_id}/turns",
        json={"prompt": "Scaffold a modern landing page"}
    )
    assert turn_res.status_code == 200
    turn_data = turn_res.json()
    assert turn_data["session_id"] == session_id
    assert turn_data["status"] == "completed"
    assert len(turn_data["events"]) >= 3
    assert turn_data["events"][0]["event_type"] == "step_start"


def test_create_project_and_approval_gate():
    # 1. Create Build Project (Generates plan, status = plan_generated, DOES NOT execute)
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Flutter Realtime Dashboard",
            "specification": "Build a dark mode voice control analytics dashboard",
            "workspace_path": "c:/Users/saisr/Projects/dashboard_app",
        }
    )
    assert create_res.status_code == 200
    project_data = create_res.json()
    project_id = project_data["project_id"]
    assert project_data["status"] == "plan_generated"
    assert "Awaiting explicit user approval" in project_data["plan_summary"]

    # 2. Get Project Status before approval
    get_res = client.get(f"/v1/build/projects/{project_id}")
    assert get_res.status_code == 200
    assert get_res.json()["status"] == "plan_generated"

    # 3. Explicit Approval Gate -> Triggers execution
    approve_res = client.post(f"/v1/build/projects/{project_id}/approve")
    assert approve_res.status_code == 200
    approve_data = approve_res.json()
    assert approve_data["status"] == "completed"
    assert "Build execution completed" in approve_data["result_summary"]
    assert len(approve_data["events"]) >= 3


def test_persistent_project_continuation_and_history():
    # 1. Create and approve project
    create_res = client.post(
        "/v1/build/projects",
        json={
            "title": "Persistent AI Assistant",
            "specification": "Build a CLI assistant",
            "workspace_path": "c:/Users/saisr/Projects/cli_assistant",
        }
    )
    project_id = create_res.json()["project_id"]
    client.post(f"/v1/build/projects/{project_id}/approve")

    # 2. List projects
    list_res = client.get("/v1/build/projects")
    assert list_res.status_code == 200
    projects = list_res.json()
    assert any(p["project_id"] == project_id for p in projects)

    # 3. Execute incremental feature turn on existing project
    inc_res = client.post(
        f"/v1/build/projects/{project_id}/turns",
        json={"prompt": "Add voice logging module to CLI assistant"}
    )
    assert inc_res.status_code == 200
    assert inc_res.json()["status"] == "completed"

    # 4. Fetch project run history
    hist_res = client.get(f"/v1/build/projects/{project_id}/history")
    assert hist_res.status_code == 200
    history = hist_res.json()
    assert len(history) >= 2  # Initial approval turn + incremental turn
    assert history[-1]["prompt"] == "Add voice logging module to CLI assistant"


