from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from ..services.build_agent import PROJECT_TYPES


class BuildRunRequest(BaseModel):
    # None -> DeepCodeService mints a fresh project id (new build).
    # Pass back a previously-returned project_id to continue working
    # in that same generated-project workspace.
    project_id: str | None = None
    task: str = Field(min_length=1, max_length=4000)


class BuildRunResponse(BaseModel):
    project_id: str
    status: str  # 'completed' | 'failed' | 'timeout'
    return_code: int | None
    stdout: str
    stderr: str
    workspace_path: str
    files: list[str]


# --- BuildJob (BuildAgent) schemas ------------------------------------------
# Separate from BuildRunRequest/Response above (DeepCode's older, still-
# working /run endpoint) -- these back the job-tracking endpoints the
# Flutter Build Workspace panel polls (POST/GET /api/build/jobs...).


class BuildJobCreateRequest(BaseModel):
    task: str = Field(min_length=1, max_length=4000)
    project_name: str = Field(min_length=1, max_length=100)
    project_type: str = Field(default='web_app')
    # Set when this build was triggered from a Build-mode conversation,
    # so the job shows up under that conversation later (see
    # GET .../jobs/by-conversation/{id}). Ownership is verified against
    # the authenticated user before use.
    conversation_id: str | None = None

    @field_validator('project_type')
    @classmethod
    def _validate_project_type(cls, v: str) -> str:
        if v not in PROJECT_TYPES:
            raise ValueError(f'project_type must be one of: {", ".join(PROJECT_TYPES)}.')
        return v


class BuildJobOut(BaseModel):
    id: str
    conversation_id: str | None
    project_name: str
    project_type: str
    request: str
    status: str
    error: str | None
    # A bool, not the raw server filesystem path -- callers download
    # via GET .../artifact instead of being handed a path on this
    # machine directly.
    has_artifact: bool
    created_at: datetime
    updated_at: datetime

    model_config = {'from_attributes': True}

    @classmethod
    def from_job(cls, job) -> 'BuildJobOut':
        return cls(
            id=job.id,
            conversation_id=job.conversation_id,
            project_name=job.project_name,
            project_type=job.project_type,
            request=job.request,
            status=job.status,
            error=job.error,
            has_artifact=bool(job.artifact_path),
            created_at=job.created_at,
            updated_at=job.updated_at,
        )


class BuildJobFilesResponse(BaseModel):
    files: list[str]


class BuildJobFileContentResponse(BaseModel):
    path: str
    content: str
