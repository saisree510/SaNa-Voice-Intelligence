import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.auth.auth_bearer import AuthenticatedUser, get_current_user
from app.adapters.deepcode_adapter import DeepCodeAdapter
from app.models.deepcode_models import DeepCodeSession, DeepCodeEvent

logger = logging.getLogger("backend.build_router")
router = APIRouter(prefix="/v1/build", tags=["Build Mode"])

# Global adapter instance for Phase 10 proof
deepcode_adapter = DeepCodeAdapter()


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
