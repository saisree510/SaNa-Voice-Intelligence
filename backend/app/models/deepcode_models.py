from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


class DeepCodeEvent(BaseModel):
    event_type: str = Field(..., description="Event type: step_start, file_edit, command_exec, step_complete, error")
    timestamp: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    message: str
    details: Optional[Dict[str, Any]] = None


class DeepCodeStep(BaseModel):
    step_index: int
    action: str
    status: str = "completed"
    description: str
    output: Optional[str] = None


class DeepCodeSession(BaseModel):
    session_id: str
    workspace_path: str
    model: str = "google/gemma-4-31b-it"
    connection_id: Optional[str] = None
    access_level: str = "full-access"
    status: str = "idle" # idle, running, completed, failed
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    steps: List[DeepCodeStep] = []


class BuildStatusEvent(BaseModel):
    session_id: str
    project_title: str
    status: str
    current_step: Optional[str] = None
    progress_percentage: int = 0
    events: List[DeepCodeEvent] = []


class BuildProjectModel(BaseModel):
    project_id: str
    user_id: str
    title: str
    specification: str
    workspace_path: str
    status: str = "drafting"  # drafting, plan_generated, approved, executing, completed, failed
    plan_summary: Optional[str] = None
    session_id: Optional[str] = None
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

