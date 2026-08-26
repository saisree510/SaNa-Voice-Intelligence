from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.models.architecture_models import (
    ArchitectureSpec,
    BlueprintStatus,
    CanvasOperation,
    validate_canvas_operation,
)


def blueprint(**changes):
    data = {
        "architecture_id": "triangle-maker",
        "project_id": "triangle-project",
        "version": 1,
        "components": [
            {"id": "web", "name": "Flutter Web", "type": "frontend"},
            {"id": "api", "name": "FastAPI", "type": "service"},
        ],
        "connections": [{"id": "web-api", "source_id": "web", "target_id": "api", "protocol": "HTTPS"}],
        "groups": [{"id": "runtime", "name": "Runtime", "component_ids": ["web", "api"]}],
    }
    data.update(changes)
    return ArchitectureSpec.model_validate(data)


def operation(operation_type, payload, **changes):
    data = {
        "operation_id": "operation-1",
        "architecture_id": "triangle-maker",
        "base_version": 1,
        "operation_type": operation_type,
        "actor": "user",
        "payload": payload,
    }
    data.update(changes)
    return CanvasOperation.model_validate(data)


def test_blueprint_accepts_meaningful_graph_without_renderer_state():
    spec = blueprint()

    assert spec.schema_version == "1.0"
    assert spec.components[0].id == "web"
    assert "x" not in spec.model_dump()["components"][0]


def test_blueprint_rejects_unknown_component_references():
    with pytest.raises(ValidationError, match="unknown component"):
        blueprint(connections=[{"id": "bad-edge", "source_id": "web", "target_id": "missing"}])


def test_approved_and_superseded_versions_require_their_timestamps():
    with pytest.raises(ValidationError, match="approved_at"):
        blueprint(status=BlueprintStatus.APPROVED)

    superseded = blueprint(status=BlueprintStatus.SUPERSEDED, superseded_at=datetime.now(timezone.utc))
    assert superseded.status is BlueprintStatus.SUPERSEDED


def test_operation_payloads_are_allowlisted_and_strict():
    with pytest.raises(ValidationError):
        operation("run_command", {})

    with pytest.raises(ValidationError):
        operation("move_node", {"component_id": "web", "x": 10, "y": 20, "command": "rm -rf"})


def test_operation_validation_rejects_conflicts_and_unknown_references():
    spec = blueprint()
    move = operation("move_node", {"component_id": "missing", "x": 10, "y": 20}, base_version=2)

    errors = validate_canvas_operation(move, spec)

    assert {error.code for error in errors} == {"version_conflict", "unknown_reference"}


def test_operation_validation_rejects_mutating_an_approved_blueprint():
    spec = blueprint(status=BlueprintStatus.APPROVED, approved_at=datetime.now(timezone.utc))
    add = operation("add_node", {"component": {"id": "database", "name": "Postgres", "type": "database"}})

    errors = validate_canvas_operation(add, spec)

    assert errors[0].code == "immutable_blueprint"
