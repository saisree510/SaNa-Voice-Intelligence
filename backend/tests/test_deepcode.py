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
