from fastapi.testclient import TestClient

from app.main import app
from conftest import auth_headers


client = TestClient(app)
USER_A = "00000000-0000-0000-0000-000000000001"
USER_B = "00000000-0000-0000-0000-000000000002"


def create_architecture(user_id: str = USER_A, title: str = "Triangle Maker") -> dict:
    response = client.post(
        "/v1/architectures",
        json={
            "title": title,
            "blueprint": {
                "architecture_id": "triangle-maker",
                "project_id": "triangle-project",
                "version": 1,
                "components": [{"id": "web", "name": "Flutter Web", "type": "frontend"}],
            },
        },
        headers=auth_headers(user_id),
    )
    assert response.status_code == 200
    return response.json()


def test_architecture_routes_require_authentication():
    assert client.get("/v1/architectures").status_code == 401
    assert client.post("/v1/architectures", json={"title": "Nope"}).status_code == 401


def test_user_can_create_list_and_read_their_architectures():
    created = create_architecture()

    list_response = client.get("/v1/architectures", headers=auth_headers(USER_A))
    assert list_response.status_code == 200
    assert any(item["architecture_id"] == created["architecture_id"] for item in list_response.json())

    get_response = client.get(f"/v1/architectures/{created['architecture_id']}", headers=auth_headers(USER_A))
    assert get_response.status_code == 200
    assert get_response.json()["user_id"] == USER_A


def test_cross_user_architecture_access_returns_not_found():
    created = create_architecture(title="Owner Only")

    response = client.get(f"/v1/architectures/{created['architecture_id']}", headers=auth_headers(USER_B))

    assert response.status_code == 404


def test_canvas_events_enforce_sequence_and_idempotency():
    created = create_architecture(title="Eventful")
    architecture_id = created["architecture_id"]
    payload = {
        "sequence_number": 1,
        "idempotency_key": "client-event-1",
        "operation": {
            "operation_id": "operation-one",
            "architecture_id": architecture_id,
            "base_version": 1,
            "operation_type": "move_node",
            "actor": "user",
            "payload": {"component_id": "web", "x": 10, "y": 20},
        },
    }

    first = client.post(f"/v1/architectures/{architecture_id}/events", json=payload, headers=auth_headers(USER_A))
    assert first.status_code == 200

    duplicate = client.post(f"/v1/architectures/{architecture_id}/events", json=payload, headers=auth_headers(USER_A))
    assert duplicate.status_code == 200
    assert duplicate.json()["event_id"] == first.json()["event_id"]

    conflict_payload = {
        **payload,
        "idempotency_key": "client-event-2",
    }
    conflict = client.post(f"/v1/architectures/{architecture_id}/events", json=conflict_payload, headers=auth_headers(USER_A))
    assert conflict.status_code == 409


def test_canvas_event_validation_rejects_unknown_component():
    created = create_architecture(title="Validation")
    architecture_id = created["architecture_id"]
    response = client.post(
        f"/v1/architectures/{architecture_id}/events",
        json={
            "sequence_number": 1,
            "idempotency_key": "bad-ref",
            "operation": {
                "operation_id": "operation-two",
                "architecture_id": architecture_id,
                "base_version": 1,
                "operation_type": "move_node",
                "actor": "user",
                "payload": {"component_id": "missing", "x": 10, "y": 20},
            },
        },
        headers=auth_headers(USER_A),
    )

    assert response.status_code == 422
    assert response.json()["detail"][0]["code"] == "unknown_reference"


def test_canvas_events_advance_the_current_blueprint():
    created = create_architecture(title="Progressive")
    architecture_id = created["architecture_id"]
    add_node = {
        "sequence_number": 1,
        "idempotency_key": "add-api",
        "operation": {
            "operation_id": "operation-add-api",
            "architecture_id": architecture_id,
            "base_version": 1,
            "operation_type": "add_node",
            "actor": "soul_agent",
            "payload": {"component": {"id": "api", "name": "FastAPI", "type": "service"}},
        },
    }
    connect = {
        "sequence_number": 2,
        "idempotency_key": "connect-web-api",
        "operation": {
            "operation_id": "operation-connect",
            "architecture_id": architecture_id,
            "base_version": 1,
            "operation_type": "connect_nodes",
            "actor": "soul_agent",
            "payload": {
                "connection": {
                    "id": "web-api",
                    "source_id": "web",
                    "target_id": "api",
                    "protocol": "HTTPS",
                }
            },
        },
    }

    add_response = client.post(f"/v1/architectures/{architecture_id}/events", json=add_node, headers=auth_headers(USER_A))
    connect_response = client.post(f"/v1/architectures/{architecture_id}/events", json=connect, headers=auth_headers(USER_A))

    assert add_response.status_code == 200
    assert connect_response.status_code == 200

    response = client.get(f"/v1/architectures/{architecture_id}", headers=auth_headers(USER_A))

    assert response.status_code == 200
    blueprint = response.json()["current_blueprint"]
    assert [component["id"] for component in blueprint["components"]] == ["web", "api"]
    assert blueprint["connections"][0]["id"] == "web-api"


def test_snapshots_and_versions_are_owner_scoped():
    created = create_architecture(title="Snapshot")
    architecture_id = created["architecture_id"]
    blueprint = created["current_blueprint"]

    snapshot = client.post(
        f"/v1/architectures/{architecture_id}/snapshots",
        json={"sequence_number": 0, "blueprint": blueprint, "scene": {"elements": []}},
        headers=auth_headers(USER_A),
    )
    assert snapshot.status_code == 200

    latest = client.get(f"/v1/architectures/{architecture_id}/snapshots/latest", headers=auth_headers(USER_A))
    assert latest.status_code == 200
    assert latest.json()["scene"]["elements"] == []

    hidden = client.get(f"/v1/architectures/{architecture_id}/snapshots/latest", headers=auth_headers(USER_B))
    assert hidden.status_code == 404

    version = client.post(
        f"/v1/architectures/{architecture_id}/versions",
        json={"blueprint": blueprint},
        headers=auth_headers(USER_A),
    )
    assert version.status_code == 200

    versions = client.get(f"/v1/architectures/{architecture_id}/versions", headers=auth_headers(USER_A))
    assert versions.status_code == 200
    assert len(versions.json()) == 1
