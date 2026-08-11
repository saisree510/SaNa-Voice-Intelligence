import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.auth.auth_bearer import AuthenticatedUser, get_current_user
from app.adapters.deepcode_adapter import DeepCodeAdapter
from app.models.deepcode_models import (
    DeepCodeSession,
    DeepCodeEvent,
    BuildProjectModel,
    BuildRunTurnModel,
)

logger = logging.getLogger("backend.build_router")
router = APIRouter(prefix="/v1/build", tags=["Build Mode"])

# Global adapter & project store
deepcode_adapter = DeepCodeAdapter()
build_projects_db: dict[str, BuildProjectModel] = {}


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
    workspace_path: str


class ApproveProjectResponse(BaseModel):
    project_id: str
    status: str
    session_id: str
    events: List[DeepCodeEvent]
    result_summary: str


@router.post("/sessions", response_model=DeepCodeSession)
async def create_build_session(
    request: CreateSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Creates a new DeepCode agentic build session for a controlled workspace.
    """
    try:
        session = deepcode_adapter.create_session(
            workspace_path=request.workspace_path,
            model=request.model or "google/gemma-4-31b-it",
            access_level=request.access_level or "full-access",
        )
        return session
    except Exception as e:
        logger.error(f"Failed to create build session: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Session creation failed: {str(e)}",
        )


@router.get("/sessions/{session_id}", response_model=DeepCodeSession)
async def get_build_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Fetches details of an active or past DeepCode build session.
    """
    session = deepcode_adapter.get_session(session_id)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build session {session_id} not found",
        )
    return session


@router.post("/sessions/{session_id}/turns", response_model=TurnResponse)
async def run_build_turn(
    session_id: str,
    request: RunTurnRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Executes an agentic build turn in a controlled DeepCode workspace.
    """
    try:
        events = []
        async for event in deepcode_adapter.run_turn(session_id, request.prompt):
            events.append(event)

        session = deepcode_adapter.get_session(session_id)
        return TurnResponse(
            session_id=session_id,
            status=session.status if session else "completed",
            events=events,
        )
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(ve))
    except Exception as e:
        logger.error(f"Build turn failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Build turn execution failed: {str(e)}",
        )


@router.post("/projects", response_model=BuildProjectModel)
async def create_build_project(
    request: CreateProjectRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Step 1: Collects project specification and generates an implementation plan (status: plan_generated).
    Entering Build Mode or drafting a project DOES NOT execute code automatically.
    """
    import os
    import re
    import uuid
    from datetime import datetime

    project_id = f"proj-{uuid.uuid4().hex[:8]}"

    # Normalize workspace path or provision a dedicated draft folder
    raw_workspace = request.workspace_path.strip() if request.workspace_path else ""
    if not raw_workspace:
        slug = re.sub(r'[^a-zA-Z0-9_-]', '_', request.title.lower())
        raw_workspace = f"c:/Users/saisr/Projects/SANA-LiveKit/drafts/{slug}_{project_id}"

    workspace_path = os.path.abspath(os.path.normpath(raw_workspace))
    os.makedirs(workspace_path, exist_ok=True)

    session = deepcode_adapter.create_session(workspace_path=workspace_path)

    project = BuildProjectModel(
        project_id=project_id,
        user_id=current_user.id,
        title=request.title,
        specification=request.specification,
        workspace_path=workspace_path,
        status="plan_generated",
        plan_summary=f"Implementation Plan generated for '{request.title}'. Awaiting explicit user approval before execution.",
        session_id=session.session_id,
        created_at=datetime.utcnow().isoformat(),
        updated_at=datetime.utcnow().isoformat(),
    )

    build_projects_db[project_id] = project
    logger.info(f"Created BuildProject {project_id} in workspace '{workspace_path}' with status 'plan_generated' awaiting explicit approval.")
    return project


@router.get("/projects/{project_id}", response_model=BuildProjectModel)
async def get_build_project(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    project = build_projects_db.get(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    if project.user_id != current_user.id and current_user.id != "dev-user-0000":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )
    return project


@router.post("/projects/{project_id}/approve", response_model=ApproveProjectResponse)
async def approve_and_execute_project(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Step 2: EXPLICIT APPROVAL GATE. Upon user approval, transitions project status to 'executing',
    runs DeepCode build turn in the workspace, and returns structured execution events and plain-text result summary.
    """
    from datetime import datetime

    project = build_projects_db.get(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    if project.user_id != current_user.id and current_user.id != "dev-user-0000":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )

    if project.status == "executing":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Project execution is already in progress.",
        )

    # Transition to executing
    project.status = "executing"
    project.updated_at = datetime.utcnow().isoformat()

    events = []
    try:
        async for event in deepcode_adapter.run_turn(
            session_id=project.session_id,
            prompt=project.specification,
        ):
            events.append(event)

        project.status = "completed"
        project.updated_at = datetime.utcnow().isoformat()

        summary = f"Build execution completed for project '{project.title}'. Generated project files and spec blueprint in workspace '{project.workspace_path}'."
        # Save run turn to project history
        import uuid
        turn_id = f"turn-{uuid.uuid4().hex[:8]}"
        run_turn = BuildRunTurnModel(
            turn_id=turn_id,
            project_id=project_id,
            session_id=project.session_id,
            prompt=project.specification,
            status="completed",
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)

        return ApproveProjectResponse(
            project_id=project_id,
            status=project.status,
            session_id=project.session_id,
            events=events,
            result_summary=summary,
        )

    except Exception as e:
        project.status = "failed"
        project.updated_at = datetime.utcnow().isoformat()
        logger.error(f"Execution failed for project {project_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Project execution failed: {str(e)}",
        )


@router.get("/projects", response_model=List[BuildProjectModel])
async def list_build_projects(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Lists all persistent build projects for the current user.
    """
    return [p for p in build_projects_db.values() if p.user_id == current_user.id or current_user.id == "dev-user-0000"]


@router.post("/projects/{project_id}/turns", response_model=TurnResponse)
async def run_project_incremental_turn(
    project_id: str,
    request: RunTurnRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Executes an incremental feature addition or bug fix turn in an existing project's DeepCode session.
    """
    import uuid
    from datetime import datetime

    project = build_projects_db.get(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    if project.user_id != current_user.id and current_user.id != "dev-user-0000":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )

    # Resume DeepCode session
    deepcode_adapter.resume_session(project.session_id)
    project.status = "executing"
    project.updated_at = datetime.utcnow().isoformat()

    events = []
    try:
        async for event in deepcode_adapter.run_turn(
            session_id=project.session_id,
            prompt=request.prompt,
        ):
            events.append(event)

        project.status = "completed"
        project.updated_at = datetime.utcnow().isoformat()

        # Save turn to history
        turn_id = f"turn-{uuid.uuid4().hex[:8]}"
        run_turn = BuildRunTurnModel(
            turn_id=turn_id,
            project_id=project_id,
            session_id=project.session_id,
            prompt=request.prompt,
            status="completed",
            events=events,
            created_at=datetime.utcnow().isoformat(),
        )
        project.history.append(run_turn)

        return TurnResponse(
            session_id=project.session_id,
            status="completed",
            events=events,
        )
    except Exception as e:
        project.status = "failed"
        project.updated_at = datetime.utcnow().isoformat()
        logger.error(f"Incremental turn failed for project {project_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Incremental turn failed: {str(e)}",
        )


@router.get("/projects/{project_id}/history", response_model=List[BuildRunTurnModel])
async def get_project_history(
    project_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Fetches complete build run turn history and step events for a project.
    """
    project = build_projects_db.get(project_id)
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Build project {project_id} not found",
        )
    if project.user_id != current_user.id and current_user.id != "dev-user-0000":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this build project",
        )
    return project.history


