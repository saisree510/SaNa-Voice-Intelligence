import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.adapters.deepcode_adapter import DeepCodeAdapter
from app.auth.auth_bearer import AuthenticatedUser, get_current_user
from app.config import settings
from app.models.deepcode_models import (
    BuildProjectModel,
    BuildRunTurnModel,
    DeepCodeEvent,
    DeepCodeSession,
)
from app.services.build_project_store import BuildProjectStore

logger = logging.getLogger("backend.build_router")
router = APIRouter(prefix="/v1/build", tags=["Build Mode"])

deepcode_adapter = DeepCodeAdapter()
project_store = BuildProjectStore(trusted_root=settings.BUILD_STORAGE_ROOT)


class CreateSessionRequest(BaseModel):
    workspace_path: str
    model: Optional[str] = "google/gemma-4-31b-it"
    access_level: Optional[str] = "full-access"


class RunTurnRequest(BaseModel):
    prompt: str


class TurnResponse(BaseModel):
    session_id: str
    status: str
    events: List[DeepCodeEvent]


class CreateProjectRequest(BaseModel):
    title: str
    specification: str
    workspace_path: Optional[str] = None


class ApproveProjectResponse(BaseModel):
    project_id: str
    status: str
    session_id: str
    events: List[DeepCodeEvent]
    result_summary: str


class BuildProjectsStatusResponse(BaseModel):
    trusted_folder: str
    projects: List[BuildProjectModel]


def _ensure_build_mode_enabled() -> None:
    if settings.BUILD_MODE_ENABLED:
        return
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=(
            "Build Mode execution is disabled on this deployment. "
            "Enable BUILD_MODE_ENABLED and configure persistent build storage to use Build Mode."
        ),
    )


def _is_dev_user(current_user: AuthenticatedUser) -> bool:
    return current_user.id == "dev-user-0000"


def _load_project_or_404(project_id: str) -> BuildProjectModel:
    project = project_store.get_project(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    return project


def _authorize_project_access(project: BuildProjectModel, current_user: AuthenticatedUser) -> None:
    if project.user_id != current_user.id and not _is_dev_user(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )


def _validate_or_default_workspace(request: CreateProjectRequest, project_id: str) -> str:
    raw_workspace = (request.workspace_path or '').strip()
    candidate_path = raw_workspace or project_store.default_workspace_path(request.title, project_id)
    try:
        return project_store.validate_workspace_path(candidate_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


def _ensure_project_session(project: BuildProjectModel) -> DeepCodeSession:
    if not project.session_id:
        session = deepcode_adapter.create_session(workspace_path=project.workspace_path)
        project.session_id = session.session_id
        project.updated_at = datetime.utcnow().isoformat()
        project_store.upsert_project(project)
        return session

    session = deepcode_adapter.get_session(project.session_id)
    if session:
        return session

    return deepcode_adapter.ensure_session(
        session_id=project.session_id,
        workspace_path=project.workspace_path,
    )


@router.post('/sessions', response_model=DeepCodeSession)
async def create_build_session(
    request: CreateSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    try:
        workspace_path = project_store.validate_workspace_path(request.workspace_path)
        session = deepcode_adapter.create_session(
            workspace_path=workspace_path,
            model=request.model or 'google/gemma-4-31b-it',
            access_level=request.access_level or 'full-access',
        )
        return session
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        logger.error('Failed to create build session: %s', exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Session creation failed: {str(exc)}',
        ) from exc


@router.get('/sessions/{session_id}', response_model=DeepCodeSession)
async def get_build_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    session = deepcode_adapter.get_session(session_id)
    if session is None:
        linked_project = project_store.find_project_by_session_id(session_id)
        if linked_project is not None:
            _authorize_project_access(linked_project, current_user)
            session = _ensure_project_session(linked_project)

    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f'Build session {session_id} not found',
        )
    return session


@router.post('/sessions/{session_id}/turns', response_model=TurnResponse)
async def run_build_turn(
    session_id: str,
    request: RunTurnRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    try:
        linked_project = project_store.find_project_by_session_id(session_id)
        if linked_project is not None:
            _authorize_project_access(linked_project, current_user)
            _ensure_project_session(linked_project)

        events = []
        async for event in deepcode_adapter.run_turn(session_id, request.prompt):
            events.append(event)

        session = deepcode_adapter.get_session(session_id)
        return TurnResponse(
            session_id=session_id,
            status=session.status if session else 'completed',
            events=events,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except Exception as exc:
        logger.error('Build turn failed: %s', exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Build turn execution failed: {str(exc)}',
        ) from exc


@router.post('/projects', response_model=BuildProjectModel)
async def create_build_project(
    request: CreateProjectRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    import os
    import uuid

    project_id = f'proj-{uuid.uuid4().hex[:8]}'
    workspace_path = _validate_or_default_workspace(request, project_id)
    os.makedirs(workspace_path, exist_ok=True)

    session = deepcode_adapter.create_session(workspace_path=workspace_path)
    timestamp = datetime.utcnow().isoformat()

    project = BuildProjectModel(
        project_id=project_id,
        user_id=current_user.id,
        title=request.title,
        specification=request.specification,
        workspace_path=workspace_path,
        status='plan_generated',
        plan_summary=(
            f"Implementation Plan generated for '{request.title}'. "
            'Awaiting explicit user approval before execution.'
        ),
        session_id=session.session_id,
        created_at=timestamp,
        updated_at=timestamp,
    )

    project_store.upsert_project(project)
    logger.info(
        'Created BuildProject %s in trusted folder %s with workspace %s.',
        project_id,
        project_store.trusted_folder(),
        workspace_path,
    )
    return project


@router.get('/projects/{project_id}', response_model=BuildProjectModel)
async def get_build_project(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)
    return project


@router.post('/projects/{project_id}/approve', response_model=ApproveProjectResponse)
async def approve_and_execute_project(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    import uuid

    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)

    if project.status == 'executing':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Project execution is already in progress.',
        )

    session = _ensure_project_session(project)
    project.status = 'executing'
    project.updated_at = datetime.utcnow().isoformat()
    project_store.upsert_project(project)

    events = []
    try:
        async for event in deepcode_adapter.run_turn(
            session_id=session.session_id,
            prompt=project.specification,
        ):
            events.append(event)

        project.status = 'completed'
        project.updated_at = datetime.utcnow().isoformat()
        run_turn = BuildRunTurnModel(
            turn_id=f"turn-{uuid.uuid4().hex[:8]}",
            project_id=project_id,
            session_id=session.session_id,
            prompt=project.specification,
            status='completed',
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)
        project_store.upsert_project(project)

        summary = (
            f"Build execution completed for project '{project.title}'. "
            f"Generated project files and spec blueprint in workspace '{project.workspace_path}'."
        )
        return ApproveProjectResponse(
            project_id=project_id,
            status=project.status,
            session_id=session.session_id,
            events=events,
            result_summary=summary,
        )

    except Exception as exc:
        project.status = 'failed'
        project.updated_at = datetime.utcnow().isoformat()
        project_store.upsert_project(project)
        logger.error('Execution failed for project %s: %s', project_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Project execution failed: {str(exc)}',
        ) from exc


@router.get('/projects', response_model=List[BuildProjectModel])
async def list_build_projects(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    return project_store.list_projects_for_user(
        user_id=current_user.id,
        is_dev_user=_is_dev_user(current_user),
    )


@router.post('/projects/{project_id}/turns', response_model=TurnResponse)
async def run_project_incremental_turn(
    project_id: str,
    request: RunTurnRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    import uuid

    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)

    session = _ensure_project_session(project)
    deepcode_adapter.resume_session(session.session_id)
    project.status = 'executing'
    project.updated_at = datetime.utcnow().isoformat()
    project_store.upsert_project(project)

    events = []
    try:
        async for event in deepcode_adapter.run_turn(
            session_id=session.session_id,
            prompt=request.prompt,
        ):
            events.append(event)

        project.status = 'completed'
        project.updated_at = datetime.utcnow().isoformat()
        run_turn = BuildRunTurnModel(
            turn_id=f"turn-{uuid.uuid4().hex[:8]}",
            project_id=project_id,
            session_id=session.session_id,
            prompt=request.prompt,
            status='completed',
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)
        project_store.upsert_project(project)

        return TurnResponse(
            session_id=session.session_id,
            status='completed',
            events=events,
        )
    except Exception as exc:
        project.status = 'failed'
        project.updated_at = datetime.utcnow().isoformat()
        project_store.upsert_project(project)
        logger.error('Incremental turn failed for project %s: %s', project_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Incremental turn failed: {str(exc)}',
        ) from exc


@router.get('/projects/{project_id}/history', response_model=List[BuildRunTurnModel])
async def get_project_history(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)
    return project.history
