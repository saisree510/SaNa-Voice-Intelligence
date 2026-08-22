import io
import logging
import os
import re
import zipfile
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import StreamingResponse
import jwt
from pydantic import BaseModel

from app.adapters.deepcode_adapter import DeepCodeAdapter
from app.auth.auth_bearer import AuthenticatedUser, get_current_user, user_id_aliases
from app.config import settings
from app.models.deepcode_models import (
    BuildFileModel,
    BuildProjectModel,
    BuildRunTurnModel,
    DeepCodeEvent,
    DeepCodeSession,
)
from app.services.build_project_store import BuildProjectStore, SupabaseBuildProjectStore

logger = logging.getLogger("backend.build_router")
router = APIRouter(prefix="/v1/build", tags=["Build Mode"])

deepcode_adapter = DeepCodeAdapter()
project_store = (
    SupabaseBuildProjectStore(
        trusted_root=settings.BUILD_STORAGE_ROOT,
        supabase_url=settings.SUPABASE_URL,
        service_role_key=settings.SUPABASE_SERVICE_ROLE_KEY,
    )
    if settings.SUPABASE_URL and settings.SUPABASE_SERVICE_ROLE_KEY
    else BuildProjectStore(trusted_root=settings.BUILD_STORAGE_ROOT)
)


def build_project_store_name() -> str:
    return 'supabase' if isinstance(project_store, SupabaseBuildProjectStore) else 'local_json_fallback'


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
    workspace_path: str
    generated_files: List[str]
    download_path: str
    download_url: str


class DownloadLinkResponse(BaseModel):
    project_id: str
    download_url: str
    expires_at: str


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


def _load_project_or_404(project_id: str) -> BuildProjectModel:
    project = project_store.get_project(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    return project


def _authorize_project_access(project: BuildProjectModel, current_user: AuthenticatedUser) -> None:
    if project.user_id not in user_id_aliases(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )


def _authorize_session_access(session: DeepCodeSession, current_user: AuthenticatedUser) -> None:
    if not session.user_id or session.user_id not in user_id_aliases(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build session",
        )


def _validate_or_default_workspace(
    request: CreateProjectRequest,
    project_id: str,
    current_user: AuthenticatedUser,
) -> str:
    raw_workspace = (request.workspace_path or '').strip()
    candidate_path = raw_workspace or project_store.default_workspace_path(
        request.title,
        project_id,
        current_user.id,
    )
    try:
        return project_store.validate_user_workspace_path(current_user.id, candidate_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


def _list_workspace_files(workspace_path: str) -> List[str]:
    collected: list[str] = []
    normalized_workspace = os.path.abspath(os.path.normpath(workspace_path))
    if not os.path.isdir(normalized_workspace):
        return collected

    for root, _, files in os.walk(normalized_workspace):
        for file_name in files:
            absolute_file = os.path.join(root, file_name)
            relative_file = os.path.relpath(absolute_file, normalized_workspace)
            collected.append(relative_file.replace("\\", "/"))
    return sorted(collected)


def _project_download_path(project_id: str) -> str:
    return f"/v1/build/projects/{project_id}/download"


def _project_signed_download_path(project_id: str) -> str:
    return f"/v1/build/projects/{project_id}/download/signed"


def _download_signing_secret() -> str:
    secret = (
        settings.BUILD_DOWNLOAD_SIGNING_SECRET
        or settings.SUPABASE_JWT_SECRET
        or settings.LIVEKIT_API_SECRET
    )
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Secure build downloads are not configured',
        )
    return secret


def _build_signed_download_token(project: BuildProjectModel, current_user: AuthenticatedUser) -> tuple[str, str]:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    payload = {
        "sub": current_user.id,
        "project_id": project.project_id,
        "purpose": "build_download",
        "exp": int(expires_at.timestamp()),
    }
    token = jwt.encode(payload, _download_signing_secret(), algorithm="HS256")
    return token, expires_at.isoformat()


def _build_signed_download_url(request: Request, project: BuildProjectModel, current_user: AuthenticatedUser) -> str:
    token, _ = _build_signed_download_token(project, current_user)
    base_url = str(request.base_url).rstrip("/")
    return f"{base_url}{_project_signed_download_path(project.project_id)}?token={token}"


def _validate_signed_download_token(project: BuildProjectModel, token: str) -> None:
    try:
        payload = jwt.decode(
            token,
            _download_signing_secret(),
            algorithms=["HS256"],
            options={"verify_aud": False},
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid download token: {str(exc)}",
        ) from exc

    if payload.get("purpose") != "build_download":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid download token purpose",
        )
    if payload.get("project_id") != project.project_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Download token does not match this project",
        )
    token_subject = payload.get("sub")
    if project.user_id not in user_id_aliases(token_subject):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Download token does not grant access to this project",
        )


def _build_archive_filename(project: BuildProjectModel) -> str:
    safe_title = re.sub(r"[^a-zA-Z0-9_-]", "_", project.title.lower()).strip("_") or project.project_id
    return f"{safe_title}_{project.project_id}.zip"


def _build_workspace_zip_bytes(workspace_path: str, generated_files: List[str]) -> bytes:
    buffer = io.BytesIO()
    normalized_workspace = os.path.abspath(os.path.normpath(workspace_path))
    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative_file in generated_files:
            normalized_relative = relative_file.replace("/", os.sep)
            absolute_file = os.path.abspath(os.path.normpath(os.path.join(normalized_workspace, normalized_relative)))
            if not os.path.isfile(absolute_file):
                continue
            try:
                if os.path.commonpath([normalized_workspace, absolute_file]) != normalized_workspace:
                    continue
            except ValueError:
                continue
            archive.write(absolute_file, arcname=relative_file)
    return buffer.getvalue()


def _build_project_archive_response(project: BuildProjectModel) -> StreamingResponse:
    generated_files = [item.path for item in project.generated_files]
    if not generated_files:
        generated_files = _list_workspace_files(project.workspace_path)
    if not generated_files:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='No generated files found for this project',
        )

    archive_bytes = _build_workspace_zip_bytes(project.workspace_path, generated_files)
    if not archive_bytes:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='No downloadable files found for this project',
        )

    headers = {
        'Content-Disposition': f'attachment; filename="{_build_archive_filename(project)}"'
    }
    return StreamingResponse(
        io.BytesIO(archive_bytes),
        media_type='application/zip',
        headers=headers,
    )


def _ensure_project_session(project: BuildProjectModel) -> DeepCodeSession:
    if not project.session_id:
        session = deepcode_adapter.create_session(
            workspace_path=project.workspace_path,
            user_id=project.user_id,
            project_id=project.project_id,
        )
        project.session_id = session.session_id
        project.updated_at = datetime.utcnow().isoformat()
        project_store.upsert_project(project)
        return session

    session = deepcode_adapter.get_session(project.session_id)
    if session:
        if session.user_id and session.user_id not in user_id_aliases(project.user_id):
            raise ValueError('Persisted project session owner does not match project owner')
        session.user_id = project.user_id
        session.project_id = project.project_id
        return session

    return deepcode_adapter.ensure_session(
        session_id=project.session_id,
        workspace_path=project.workspace_path,
        user_id=project.user_id,
        project_id=project.project_id,
    )


@router.post('/sessions', response_model=DeepCodeSession)
async def create_build_session(
    request: CreateSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    try:
        workspace_path = project_store.validate_user_workspace_path(
            current_user.id,
            request.workspace_path,
        )
        session = deepcode_adapter.create_session(
            workspace_path=workspace_path,
            model=request.model or 'google/gemma-4-31b-it',
            access_level=request.access_level or 'full-access',
            user_id=current_user.id,
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
    if session is not None:
        _authorize_session_access(session, current_user)
    else:
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
            session = _ensure_project_session(linked_project)
        else:
            session = deepcode_adapter.get_session(session_id)
            if session is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f'Build session {session_id} not found',
                )
            _authorize_session_access(session, current_user)

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
    except HTTPException:
        raise
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
    workspace_path = _validate_or_default_workspace(request, project_id, current_user)
    os.makedirs(workspace_path, exist_ok=True)

    session = deepcode_adapter.create_session(
        workspace_path=workspace_path,
        user_id=current_user.id,
        project_id=project_id,
    )
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


async def _approve_and_execute_project_model(
    project: BuildProjectModel,
    request: Request,
    current_user: AuthenticatedUser,
) -> ApproveProjectResponse:
    import uuid

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

        generated_files = _list_workspace_files(project.workspace_path)
        if not generated_files:
            raise RuntimeError(
                f"Build execution completed for project '{project.title}' but produced no files in workspace '{project.workspace_path}'."
            )

        project.status = 'completed'
        project.updated_at = datetime.utcnow().isoformat()
        run_id = f"turn-{uuid.uuid4().hex[:8]}"
        run_turn = BuildRunTurnModel(
            turn_id=run_id,
            project_id=project.project_id,
            session_id=session.session_id,
            user_id=project.user_id,
            prompt=project.specification,
            status='completed',
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)
        project.generated_files = [
            BuildFileModel(
                path=file_path,
                user_id=project.user_id,
                project_id=project.project_id,
                run_id=run_id,
            )
            for file_path in generated_files
        ]
        project_store.upsert_project(project)

        summary = (
            f"Build execution completed for project '{project.title}'. "
            f"Generated {len(generated_files)} file(s) in workspace '{project.workspace_path}'."
        )
        return ApproveProjectResponse(
            project_id=project.project_id,
            status=project.status,
            session_id=session.session_id,
            events=events,
            result_summary=summary,
            workspace_path=project.workspace_path,
            generated_files=generated_files,
            download_path=_project_download_path(project.project_id),
            download_url=_build_signed_download_url(request, project, current_user),
        )

    except Exception as exc:
        project.status = 'failed'
        project.updated_at = datetime.utcnow().isoformat()
        project_store.upsert_project(project)
        logger.error('Execution failed for project %s: %s', project.project_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Project execution failed: {str(exc)}',
        ) from exc


@router.post('/projects/approve-latest', response_model=ApproveProjectResponse)
async def approve_and_execute_latest_project(
    request: Request,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = project_store.find_latest_project_for_user(
        user_id=current_user.id,
        statuses=('plan_generated',),
    )
    if project is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='No pending build project found to approve',
        )
    _authorize_project_access(project, current_user)
    return await _approve_and_execute_project_model(project, request, current_user)


@router.post('/projects/{project_id}/approve', response_model=ApproveProjectResponse)
async def approve_and_execute_project(
    project_id: str,
    request: Request,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)
    return await _approve_and_execute_project_model(project, request, current_user)


@router.get('/projects/{project_id}/download-link', response_model=DownloadLinkResponse)
async def get_project_download_link(
    project_id: str,
    request: Request,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)
    _, expires_at = _build_signed_download_token(project, current_user)
    return DownloadLinkResponse(
        project_id=project.project_id,
        download_url=_build_signed_download_url(request, project, current_user),
        expires_at=expires_at,
    )


@router.get('/projects/{project_id}/download')
async def download_project_files(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _authorize_project_access(project, current_user)
    return _build_project_archive_response(project)


@router.get('/projects/{project_id}/download/signed', name='download_project_files_signed')
async def download_project_files_signed(
    project_id: str,
    token: str = Query(...),
):
    _ensure_build_mode_enabled()
    project = _load_project_or_404(project_id)
    _validate_signed_download_token(project, token)
    return _build_project_archive_response(project)


@router.get('/projects', response_model=List[BuildProjectModel])
async def list_build_projects(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    _ensure_build_mode_enabled()
    projects = project_store.list_projects_for_user(
        user_id=current_user.id,
    )
    return projects


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
        run_id = f"turn-{uuid.uuid4().hex[:8]}"
        generated_files = _list_workspace_files(project.workspace_path)
        run_turn = BuildRunTurnModel(
            turn_id=run_id,
            project_id=project_id,
            session_id=session.session_id,
            user_id=project.user_id,
            prompt=request.prompt,
            status='completed',
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)
        project.generated_files = [
            BuildFileModel(
                path=file_path,
                user_id=project.user_id,
                project_id=project.project_id,
                run_id=run_id,
            )
            for file_path in generated_files
        ]
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
