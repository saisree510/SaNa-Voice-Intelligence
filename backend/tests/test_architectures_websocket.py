import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import app
from conftest import auth_token


client = TestClient(app)
USER_A = "00000000-0000-0000-0000-000000000001"
USER_B = "00000000-0000-0000-0000-000000000002"


def create_architecture(user_id: str = USER_A) -> str:
    response = client.post(
        "/v1/architectures",
        json={
            "title": "Live Canvas",
            "blueprint": {
                "architecture_id": "live-canvas",
                "version": 1,
                "components": [{"id": "web", "name": "Flutter Web", "type": "frontend"}],
            },
        },
        headers={"Authorization": f"Bearer {auth_token(user_id)}"},
    )
    assert response.status_code == 200
    return response.json()["architecture_id"]


def canvas_operation(architecture_id: str, *, sequence_number: int = 1, idempotency_key: str = "ws-1") -> dict:
    return {
        "type": "canvas_operation",
        "sequence_number": sequence_number,
        "idempotency_key": idempotency_key,
        "operation": {
            "operation_id": f"operation-{sequence_number}",
            "architecture_id": architecture_id,
            "base_version": 1,
            "operation_type": "move_node",
            "actor": "user",
            "payload": {"component_id": "web", "x": sequence_number * 10, "y": 20},
        },
    }


def test_architecture_websocket_requires_valid_token():
    architecture_id = create_architecture()

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token=bad-token"):
            pass


def test_architecture_websocket_rejects_cross_user_access():
    architecture_id = create_architecture(USER_A)

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token={auth_token(USER_B)}"):
            pass


def test_architecture_websocket_accepts_and_persists_valid_operation():
    architecture_id = create_architecture()

    with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token={auth_token(USER_A)}") as websocket:
        assert websocket.receive_json()["type"] == "canvas_ready"
        websocket.send_json(canvas_operation(architecture_id))
        accepted = websocket.receive_json()

    assert accepted["type"] == "canvas_accepted"
    assert accepted["event"]["sequence_number"] == 1

    events = client.get(
        f"/v1/architectures/{architecture_id}/events",
        headers={"Authorization": f"Bearer {auth_token(USER_A)}"},
    )
    assert events.status_code == 200
    assert len(events.json()) == 1


def test_architecture_websocket_returns_safe_rejection_for_invalid_operation():
    architecture_id = create_architecture()
    invalid = canvas_operation(architecture_id)
    invalid["operation"]["payload"]["component_id"] = "missing"

    with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token={auth_token(USER_A)}") as websocket:
        websocket.receive_json()
        websocket.send_json(invalid)
        rejected = websocket.receive_json()

    assert rejected["type"] == "canvas_rejected"
    assert rejected["code"] == "operation_rejected"
    assert rejected["status_code"] == 422


def test_architecture_websocket_broadcasts_to_other_authorized_canvas_clients():
    architecture_id = create_architecture()
    token = auth_token(USER_A)

    with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token={token}") as first:
        with client.websocket_connect(f"/v1/architectures/{architecture_id}/ws?token={token}") as second:
            assert first.receive_json()["type"] == "canvas_ready"
            assert second.receive_json()["type"] == "canvas_ready"
            first.send_json(canvas_operation(architecture_id))
            assert first.receive_json()["type"] == "canvas_accepted"
            broadcast = second.receive_json()

    assert broadcast["type"] == "canvas_event"
    assert broadcast["event"]["operation"]["operation_type"] == "move_node"
