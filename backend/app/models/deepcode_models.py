from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


class DeepCodeEvent(BaseModel):
    event_type: str = Field(..., description="Event type: step_start, file_edit, command_exec, step_complete, error")
    timestamp: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    message: str
    details: Optional[Dict[str, Any]] = None
    user_id: Optional[str] = None
    project_id: Optional[str] = None
    session_id: Optional[str] = None


class DeepCodeStep(BaseModel):
    step_index: int
    action: str
    status: str = "completed"
    description: str
    output: Optional[str] = None


class DeepCodeSession(BaseModel):
    session_id: str
    workspace_path: str
    user_id: Optional[str] = None
    project_id: Optional[str] = None
    model: str = "google/gemma-4-31b-it"
    connection_id: Optional[str] = None
    access_level: str = "full-access"
    status: str = "idle"  # idle, running, completed, failed
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    steps: List[DeepCodeStep] = Field(default_factory=list)


class BuildStatusEvent(BaseModel):
    session_id: str
    project_title: str
    status: str
    current_step: Optional[str] = None
    progress_percentage: int = 0
    events: List[DeepCodeEvent] = Field(default_factory=list)


class BuildRunTurnModel(BaseModel):
    turn_id: str
    project_id: str
    session_id: str
    user_id: Optional[str] = None
    prompt: str
    status: str = "completed"
    provider: str = "prototype_scaffold"  # "deepcode" | "prototype_scaffold"
    blueprint_hash: Optional[str] = None
    events: List[DeepCodeEvent] = Field(default_factory=list)
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())


class BuildFileModel(BaseModel):
    path: str
    user_id: str
    project_id: str
    run_id: str


class BuildProjectModel(BaseModel):
    project_id: str
    user_id: str
    title: str
    specification: str
    workspace_path: str
    status: str = "drafting"  # drafting, plan_generated, approved, executing, completed, failed
    plan_summary: Optional[str] = None
    session_id: Optional[str] = None
    artifact_path: Optional[str] = None
    architecture_id: Optional[str] = None
    blueprint_version: Optional[int] = None
    blueprint_hash: Optional[str] = None
    provider: str = "prototype_scaffold"  # "deepcode" | "prototype_scaffold"
    scaffold_confirmed: bool = False  # explicit user consent to run on Prototype Scaffold instead of DeepCode
    history: List[BuildRunTurnModel] = Field(default_factory=list)
    generated_files: List[BuildFileModel] = Field(default_factory=list)
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
