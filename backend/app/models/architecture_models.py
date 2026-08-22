"""Provider-neutral Architecture Blueprint and canvas operation contracts.

The Blueprint holds architectural meaning only. Rendering libraries own positions,
styles and scene data; those are communicated through bounded canvas operations.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator


ID_PATTERN = r"^[a-z][a-z0-9_-]{0,63}$"


class BlueprintStatus(str, Enum):
    DRAFT = "draft"
    APPROVED = "approved"
    SUPERSEDED = "superseded"


class CanvasOperationType(str, Enum):
    ADD_NODE = "add_node"
    UPDATE_NODE = "update_node"
    MOVE_NODE = "move_node"
    DELETE_NODE = "delete_node"
    CONNECT_NODES = "connect_nodes"
    DISCONNECT_NODES = "disconnect_nodes"
    CREATE_GROUP = "create_group"
    ADD_ANNOTATION = "add_annotation"
    HIGHLIGHT_RISK = "highlight_risk"
    FOCUS_VIEWPORT = "focus_viewport"


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ArchitectureComponent(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    name: str = Field(min_length=1, max_length=120)
    type: str = Field(min_length=1, max_length=64)
    technology: Optional[str] = Field(default=None, max_length=120)
    metadata: dict[str, Any] = Field(default_factory=dict)


class ArchitectureConnection(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    source_id: str = Field(pattern=ID_PATTERN)
    target_id: str = Field(pattern=ID_PATTERN)
    protocol: Optional[str] = Field(default=None, max_length=80)
    direction: Literal["unidirectional", "bidirectional"] = "unidirectional"
    label: Optional[str] = Field(default=None, max_length=160)

    @model_validator(mode="after")
    def endpoints_must_differ(self):
        if self.source_id == self.target_id:
            raise ValueError("connection source_id and target_id must differ")
        return self


class ArchitectureGroup(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    name: str = Field(min_length=1, max_length=120)
    component_ids: list[str] = Field(default_factory=list, max_length=100)


class ArchitectureAnnotation(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    text: str = Field(min_length=1, max_length=500)
    component_ids: list[str] = Field(default_factory=list, max_length=20)


class ArchitectureDecision(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    title: str = Field(min_length=1, max_length=160)
    rationale: str = Field(min_length=1, max_length=1000)
    status: Literal["proposed", "accepted", "rejected"] = "proposed"


class ArchitectureRisk(ContractModel):
    id: str = Field(pattern=ID_PATTERN)
    title: str = Field(min_length=1, max_length=160)
    severity: Literal["low", "medium", "high", "critical"]
    mitigation: Optional[str] = Field(default=None, max_length=1000)


class ArchitectureSpec(ContractModel):
    """Canonical Architecture Blueprint; never store renderer scene JSON here."""

    schema_version: Literal["1.0"] = "1.0"
    architecture_id: str = Field(pattern=ID_PATTERN)
    project_id: Optional[str] = Field(default=None, pattern=ID_PATTERN)
    version: int = Field(ge=1)
    status: BlueprintStatus = BlueprintStatus.DRAFT
    view_type: Literal["overview"] = "overview"
    components: list[ArchitectureComponent] = Field(default_factory=list, max_length=200)
    connections: list[ArchitectureConnection] = Field(default_factory=list, max_length=400)
    groups: list[ArchitectureGroup] = Field(default_factory=list, max_length=50)
    annotations: list[ArchitectureAnnotation] = Field(default_factory=list, max_length=100)
    decisions: list[ArchitectureDecision] = Field(default_factory=list, max_length=100)
    risks: list[ArchitectureRisk] = Field(default_factory=list, max_length=100)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    approved_at: Optional[datetime] = None
    superseded_at: Optional[datetime] = None

    @model_validator(mode="after")
    def validate_graph_and_version_state(self):
        collections = (self.components, self.connections, self.groups, self.annotations, self.decisions, self.risks)
        all_ids = [item.id for collection in collections for item in collection]
        if len(all_ids) != len(set(all_ids)):
            raise ValueError("Blueprint element IDs must be stable and globally unique")

        component_ids = {component.id for component in self.components}
        for connection in self.connections:
            if connection.source_id not in component_ids or connection.target_id not in component_ids:
                raise ValueError(f"connection {connection.id} references an unknown component")
        for group in self.groups:
            if len(group.component_ids) != len(set(group.component_ids)):
                raise ValueError(f"group {group.id} contains duplicate component IDs")
            if not set(group.component_ids).issubset(component_ids):
                raise ValueError(f"group {group.id} references an unknown component")
        for annotation in self.annotations:
            if not set(annotation.component_ids).issubset(component_ids):
                raise ValueError(f"annotation {annotation.id} references an unknown component")

        if self.status is BlueprintStatus.APPROVED and self.approved_at is None:
            raise ValueError("approved Blueprint versions require approved_at")
        if self.status is BlueprintStatus.SUPERSEDED and self.superseded_at is None:
            raise ValueError("superseded Blueprint versions require superseded_at")
        if self.status is BlueprintStatus.DRAFT and (self.approved_at or self.superseded_at):
            raise ValueError("draft Blueprint versions cannot have approval or supersession timestamps")
        return self


class OperationPayload(ContractModel):
    pass


class AddNodePayload(OperationPayload):
    component: ArchitectureComponent


class UpdateNodePayload(OperationPayload):
    component_id: str = Field(pattern=ID_PATTERN)
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    type: Optional[str] = Field(default=None, min_length=1, max_length=64)
    technology: Optional[str] = Field(default=None, max_length=120)
    metadata: Optional[dict[str, Any]] = None

    @model_validator(mode="after")
    def has_a_change(self):
        if all(value is None for value in (self.name, self.type, self.technology, self.metadata)):
            raise ValueError("update_node requires at least one mutable component property")
        return self


class MoveNodePayload(OperationPayload):
    component_id: str = Field(pattern=ID_PATTERN)
    x: float
    y: float


class DeleteNodePayload(OperationPayload):
    component_id: str = Field(pattern=ID_PATTERN)


class ConnectNodesPayload(OperationPayload):
    connection: ArchitectureConnection


class DisconnectNodesPayload(OperationPayload):
    connection_id: str = Field(pattern=ID_PATTERN)


class CreateGroupPayload(OperationPayload):
    group: ArchitectureGroup


class AddAnnotationPayload(OperationPayload):
    annotation: ArchitectureAnnotation


class HighlightRiskPayload(OperationPayload):
    risk_id: str = Field(pattern=ID_PATTERN)


class FocusViewportPayload(OperationPayload):
    x: float
    y: float
    zoom: float = Field(gt=0, le=4)


PAYLOAD_MODELS: dict[CanvasOperationType, type[OperationPayload]] = {
    CanvasOperationType.ADD_NODE: AddNodePayload,
    CanvasOperationType.UPDATE_NODE: UpdateNodePayload,
    CanvasOperationType.MOVE_NODE: MoveNodePayload,
    CanvasOperationType.DELETE_NODE: DeleteNodePayload,
    CanvasOperationType.CONNECT_NODES: ConnectNodesPayload,
    CanvasOperationType.DISCONNECT_NODES: DisconnectNodesPayload,
    CanvasOperationType.CREATE_GROUP: CreateGroupPayload,
    CanvasOperationType.ADD_ANNOTATION: AddAnnotationPayload,
    CanvasOperationType.HIGHLIGHT_RISK: HighlightRiskPayload,
    CanvasOperationType.FOCUS_VIEWPORT: FocusViewportPayload,
}


class CanvasOperation(ContractModel):
    operation_id: str = Field(pattern=ID_PATTERN)
    architecture_id: str = Field(pattern=ID_PATTERN)
    base_version: int = Field(ge=1)
    operation_type: CanvasOperationType
    actor: Literal["user", "soul_agent", "system"]
    payload: dict[str, Any]

    @field_validator("payload")
    @classmethod
    def payload_must_be_an_object(cls, value):
        if not isinstance(value, dict):
            raise ValueError("operation payload must be an object")
        return value

    @model_validator(mode="after")
    def validate_payload_shape(self):
        PAYLOAD_MODELS[self.operation_type].model_validate(self.payload)
        return self


class CanvasValidationError(ContractModel):
    code: Literal["version_conflict", "unknown_reference", "duplicate_id", "immutable_blueprint"]
    message: str
    path: str


def validate_canvas_operation(operation: CanvasOperation, blueprint: ArchitectureSpec) -> list[CanvasValidationError]:
    """Return safe, structured rejections without mutating the Blueprint."""
    errors: list[CanvasValidationError] = []
    if blueprint.status is not BlueprintStatus.DRAFT:
        errors.append(CanvasValidationError(code="immutable_blueprint", message="only draft Blueprints accept canvas operations", path="status"))
    if operation.architecture_id != blueprint.architecture_id or operation.base_version != blueprint.version:
        errors.append(CanvasValidationError(code="version_conflict", message="operation does not match the current Blueprint version", path="base_version"))

    payload = PAYLOAD_MODELS[operation.operation_type].model_validate(operation.payload)
    component_ids = {component.id for component in blueprint.components}
    connection_ids = {connection.id for connection in blueprint.connections}
    all_ids = component_ids | connection_ids | {item.id for item in blueprint.groups + blueprint.annotations + blueprint.decisions + blueprint.risks}

    def unknown(reference: str, path: str):
        if reference not in component_ids:
            errors.append(CanvasValidationError(code="unknown_reference", message=f"unknown component: {reference}", path=path))

    if isinstance(payload, AddNodePayload) and payload.component.id in all_ids:
        errors.append(CanvasValidationError(code="duplicate_id", message="component ID already exists", path="payload.component.id"))
    elif isinstance(payload, (UpdateNodePayload, MoveNodePayload, DeleteNodePayload)):
        unknown(payload.component_id, "payload.component_id")
    elif isinstance(payload, ConnectNodesPayload):
        if payload.connection.id in all_ids:
            errors.append(CanvasValidationError(code="duplicate_id", message="connection ID already exists", path="payload.connection.id"))
        unknown(payload.connection.source_id, "payload.connection.source_id")
        unknown(payload.connection.target_id, "payload.connection.target_id")
    elif isinstance(payload, DisconnectNodesPayload) and payload.connection_id not in connection_ids:
        errors.append(CanvasValidationError(code="unknown_reference", message=f"unknown connection: {payload.connection_id}", path="payload.connection_id"))
    elif isinstance(payload, CreateGroupPayload):
        if payload.group.id in all_ids:
            errors.append(CanvasValidationError(code="duplicate_id", message="group ID already exists", path="payload.group.id"))
        for component_id in payload.group.component_ids:
            unknown(component_id, "payload.group.component_ids")
    elif isinstance(payload, AddAnnotationPayload):
        if payload.annotation.id in all_ids:
            errors.append(CanvasValidationError(code="duplicate_id", message="annotation ID already exists", path="payload.annotation.id"))
        for component_id in payload.annotation.component_ids:
            unknown(component_id, "payload.annotation.component_ids")
    elif isinstance(payload, HighlightRiskPayload) and payload.risk_id not in {risk.id for risk in blueprint.risks}:
        errors.append(CanvasValidationError(code="unknown_reference", message=f"unknown risk: {payload.risk_id}", path="payload.risk_id"))
    return errors


__all__ = ["ArchitectureSpec", "BlueprintStatus", "CanvasOperation", "CanvasOperationType", "CanvasValidationError", "ValidationError", "validate_canvas_operation"]
