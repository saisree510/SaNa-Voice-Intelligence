import asyncio
import json
import logging
import uuid
from typing import AsyncGenerator, Dict, Optional
from datetime import datetime

from app.models.deepcode_models import (
    DeepCodeEvent,
    DeepCodeSession,
    DeepCodeStep,
    BuildStatusEvent,
)

logger = logging.getLogger("backend.deepcode_adapter")


class DeepCodeAdapter:
    """
    Adapter abstraction insulating SaNa backend from DeepCode agentic build engine CLI/JSON details.
    """

    def __init__(self):
        self._sessions: Dict[str, DeepCodeSession] = {}

    def create_session(
        self,
        workspace_path: str,
        model: str = "google/gemma-4-31b-it",
        connection_id: Optional[str] = None,
        access_level: str = "full-access",
    ) -> DeepCodeSession:
        session_id = f"dc-sess-{uuid.uuid4().hex[:8]}"
        session = DeepCodeSession(
            session_id=session_id,
            workspace_path=workspace_path,
            model=model,
            connection_id=connection_id,
            access_level=access_level,
            status="idle",
        )
        self._sessions[session_id] = session
        logger.info(f"Created DeepCode session {session_id} for workspace {workspace_path}")
        return session

    def get_session(self, session_id: str) -> Optional[DeepCodeSession]:
        return self._sessions.get(session_id)

    async def run_turn(
        self,
        session_id: str,
        prompt: str,
    ) -> AsyncGenerator[DeepCodeEvent, None]:
        """
        Executes a turn in the DeepCode build session and yields structured JSON events.
        """
        session = self._sessions.get(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")

        session.status = "running"
        session.updated_at = datetime.utcnow().isoformat()

        # Emit turn initialization event
        yield DeepCodeEvent(
            event_type="step_start",
            message=f"Starting DeepCode turn for session {session_id}",
            details={"prompt": prompt, "workspace": session.workspace_path},
        )
        await asyncio.sleep(0.1)

        # Simulate step 1: Requirements analysis
        step1 = DeepCodeStep(
            step_index=1,
            action="analyze_requirements",
            status="completed",
            description=f"Analyzed prompt: '{prompt}'",
            output="Project specification parsed successfully.",
        )
        session.steps.append(step1)
        yield DeepCodeEvent(
            event_type="file_edit",
            message="Generated project blueprint and spec file",
            details={"step": step1.dict()},
        )
        await asyncio.sleep(0.1)

        # Simulate step 2: Execution proof
        step2 = DeepCodeStep(
            step_index=2,
            action="execute_build",
            status="completed",
            description="Scaffolded files in workspace.",
            output="Built project target successfully.",
        )
        session.steps.append(step2)
        yield DeepCodeEvent(
            event_type="step_complete",
            message="DeepCode build turn completed successfully",
            details={"step": step2.dict()},
        )

        session.status = "completed"
        session.updated_at = datetime.utcnow().isoformat()

    def resume_session(self, session_id: str) -> DeepCodeSession:
        """
        Resumes an existing session for continued build turns.
        """
        session = self._sessions.get(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")
        session.status = "idle"
        session.updated_at = datetime.utcnow().isoformat()
        logger.info(f"Resumed DeepCode session {session_id}")
        return session
