from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.auth.auth_bearer import AuthenticatedUser, get_current_user, user_id_aliases
from app.config import settings
from app.models.architecture_models import ArchitectureSpec, BlueprintStatus, CanvasOperation, validate_canvas_operation
from app.models.architecture_storage_models import (
    ArchitectureRecord,
    ArchitectureVersionRecord,
    CanvasEventRecord,
    CanvasSnapshotRecord,
)
from app.services.architecture_store import (
    ArchitectureStore,
    DuplicateIdempotencyError,
    SequenceConflictError,
    SupabaseArchitectureStore,
    new_architecture_id,
)

router = APIRouter(prefix="/v1/architectures", tags=["Architectures"])

architecture_store = (
    SupabaseArchitectureStore(
        supabase_url=settings.SUPABASE_URL,
        service_role_key=settings.SUPABASE_SERVICE_ROLE_KEY,
    )
    if settings.SUPABASE_URL and settings.SUPABASE_SERVICE_ROLE_KEY
    else ArchitectureStore(trusted_root=settings.BUILD_STORAGE_ROOT)
)


class CreateArchitectureRequest(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    conversation_id: Optional[str] = None
    project_id: Optional[str] = None
    blueprint: Optional[ArchitectureSpec] = None


class UpdateArchitectureRequest(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=160)
    current_blueprint: Optional[ArchitectureSpec] = None


class AppendCanvasEventRequest(BaseModel):
    sequence_number: int = Field(ge=1)
    idempotency_key: str = Field(min_length=1, max_length=120)
    operation: CanvasOperation


class CreateSnapshotRequest(BaseModel):
    sequence_number: int = Field(ge=0)
    blueprint: ArchitectureSpec
    scene: dict[str, Any] = Field(default_factory=dict)


class CreateVersionRequest(BaseModel):
    blueprint: ArchitectureSpec


def architecture_store_name() -> str:
    return "supabase" if isinstance(architecture_store, SupabaseArchitectureStore) else "local_json_fallback"


def _default_blueprint(architecture_id: str, project_id: Optional[str] = None) -> ArchitectureSpec:
    return ArchitectureSpec(
        architecture_id=architecture_id,
        project_id=project_id,
        version=1,
    )


def _load_owned_architecture_or_404(architecture_id: str, current_user: AuthenticatedUser) -> ArchitectureRecord:
    record = architecture_store.get_architecture(architecture_id)
    if record is None or record.user_id not in user_id_aliases(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Architecture {architecture_id} not found",
        )
    return record


@router.post("", response_model=ArchitectureRecord)
async def create_architecture(
    request: CreateArchitectureRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    architecture_id = request.blueprint.architecture_id if request.blueprint else new_architecture_id()
    blueprint = request.blueprint or _default_blueprint(architecture_id, request.project_id)
    if blueprint.architecture_id != architecture_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Blueprint architecture_id mismatch")

    record = ArchitectureRecord(
        architecture_id=architecture_id,
        user_id=current_user.id,
        title=request.title,
        conversation_id=request.conversation_id,
        project_id=request.project_id,
        current_version=blueprint.version,
        current_blueprint=blueprint,
    )
    return architecture_store.create_architecture(record)


@router.get("", response_model=list[ArchitectureRecord])
async def list_architectures(current_user: AuthenticatedUser = Depends(get_current_user)):
    return architecture_store.list_architectures_for_user(current_user.id)


@router.get("/{architecture_id}", response_model=ArchitectureRecord)
async def get_architecture(
    architecture_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    return _load_owned_architecture_or_404(architecture_id, current_user)


@router.patch("/{architecture_id}", response_model=ArchitectureRecord)
async def update_architecture(
    architecture_id: str,
    request: UpdateArchitectureRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    record = _load_owned_architecture_or_404(architecture_id, current_user)
    if request.title is not None:
        record.title = request.title
    if request.current_blueprint is not None:
        if request.current_blueprint.architecture_id != record.architecture_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Blueprint architecture_id mismatch")
        record.current_blueprint = request.current_blueprint
        record.current_version = request.current_blueprint.version
    return architecture_store.update_architecture(record)


@router.post("/{architecture_id}/events", response_model=CanvasEventRecord)
async def append_canvas_event(
    architecture_id: str,
    request: AppendCanvasEventRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    record = _load_owned_architecture_or_404(architecture_id, current_user)
    if request.operation.architecture_id != architecture_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Operation architecture_id mismatch")

    validation_errors = validate_canvas_operation(request.operation, record.current_blueprint)
    if validation_errors:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=[error.model_dump(mode="json") for error in validation_errors],
        )

    event = CanvasEventRecord(
        event_id=new_architecture_id("evt"),
        architecture_id=architecture_id,
        user_id=current_user.id,
        architecture_version=record.current_version,
        sequence_number=request.sequence_number,
        idempotency_key=request.idempotency_key,
        event_type=request.operation.operation_type.value,
        operation=request.operation,
    )
    try:
        return architecture_store.append_event(event)
    except DuplicateIdempotencyError as exc:
        return exc.existing_event
    except SequenceConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.get("/{architecture_id}/events", response_model=list[CanvasEventRecord])
async def list_canvas_events(
    architecture_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _load_owned_architecture_or_404(architecture_id, current_user)
    return architecture_store.list_events(architecture_id)


@router.post("/{architecture_id}/snapshots", response_model=CanvasSnapshotRecord)
async def create_canvas_snapshot(
    architecture_id: str,
    request: CreateSnapshotRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    record = _load_owned_architecture_or_404(architecture_id, current_user)
    if request.blueprint.architecture_id != architecture_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Snapshot blueprint architecture_id mismatch")
    snapshot = CanvasSnapshotRecord(
        snapshot_id=new_architecture_id("snap"),
        architecture_id=architecture_id,
        user_id=current_user.id,
        architecture_version=record.current_version,
        sequence_number=request.sequence_number,
        blueprint=request.blueprint,
        scene=request.scene,
    )
    return architecture_store.create_snapshot(snapshot)


@router.get("/{architecture_id}/snapshots/latest", response_model=CanvasSnapshotRecord)
async def get_latest_canvas_snapshot(
    architecture_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _load_owned_architecture_or_404(architecture_id, current_user)
    snapshot = architecture_store.latest_snapshot(architecture_id)
    if snapshot is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No canvas snapshot found")
    return snapshot


@router.post("/{architecture_id}/versions", response_model=ArchitectureVersionRecord)
async def create_architecture_version(
    architecture_id: str,
    request: CreateVersionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    record = _load_owned_architecture_or_404(architecture_id, current_user)
    if request.blueprint.architecture_id != architecture_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Version blueprint architecture_id mismatch")
    if request.blueprint.status is BlueprintStatus.DRAFT:
        blueprint = request.blueprint.model_copy(update={"version": record.current_version})
    else:
        blueprint = request.blueprint

    version = ArchitectureVersionRecord(
        version_id=new_architecture_id("ver"),
        architecture_id=architecture_id,
        user_id=current_user.id,
        version_number=blueprint.version,
        blueprint=blueprint,
    )
    return architecture_store.create_version(version)


@router.get("/{architecture_id}/versions", response_model=list[ArchitectureVersionRecord])
async def list_architecture_versions(
    architecture_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _load_owned_architecture_or_404(architecture_id, current_user)
    return architecture_store.list_versions(architecture_id)
