import logging
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..db.session import get_db
from ..models.conversation import Conversation
from ..models.user import User
from ..schemas.build import (
    BuildJobCreateRequest,
    BuildJobFileContentResponse,
    BuildJobFilesResponse,
    BuildJobOut,
    BuildRunRequest,
    BuildRunResponse,
)
from ..services import build_job_service as jobs
from ..services.build_agent import BuildAgent, list_workspace_files
from ..services.build_workspace import BuildWorkspaceError, safe_relative_path
from ..services.deepcode_service import DeepCodeConfigError, DeepCodeService, DeepCodeServiceError
from ..services.file_access import MAX_FILE_BYTES
from .deps import get_current_user, get_current_user_allow_query_token

logger = logging.getLogger('sana-backend')

router = APIRouter(prefix='/api/build', tags=['build'])


@lru_cache
def get_deepcode_service() -> DeepCodeService:
    # Same pattern as ai_service.py's get_ai_provider() -- one shared
    # instance, config resolved (and validated -- see
    # DeepCodeService._resolve_workspaces_root) once, not per request.
    return DeepCodeService()


@lru_cache
def get_build_agent() -> BuildAgent:
    # BuildAgent is stateless (see its own docstring) and shares the
    # same workspace root validation as DeepCodeService -- one instance
    # is enough, resolved (and validated) once at first use.
    return BuildAgent()


@router.post('/run', response_model=BuildRunResponse)
async def run_build(
    body: BuildRunRequest,
    user: User = Depends(get_current_user),
    deepcode: DeepCodeService = Depends(get_deepcode_service),
) -> BuildRunResponse:
    """SANA Build mode's original entry point into DeepCode -- kept
    working as-is. The job-tracking endpoints below (POST/GET
    .../jobs...) are the newer, BuildAgent-backed path the Flutter
    Build Workspace panel and Build-mode conversations actually use;
    this route is unrelated to and untouched by that change.
    """
    try:
        result = await deepcode.run_task(project_id=body.project_id, task=body.task)
    except DeepCodeServiceError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except DeepCodeConfigError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e

    return BuildRunResponse(
        project_id=result.project_id,
        status=result.status,
        return_code=result.return_code,
        stdout=result.stdout,
        stderr=result.stderr,
        workspace_path=result.workspace_path,
        files=result.files,
    )


# --- BuildJob endpoints (BuildAgent) ---------------------------------------
# Track a build through PENDING -> ... -> COMPLETED/FAILED (see
# build_job_service.py's status constants) so the Flutter Build
# Workspace panel can show a live progress checklist instead of one
# opaque request/response, and afterward list/read/download the
# generated files. Runs as a FastAPI BackgroundTask -- no queue/worker
# process needed for v1, matches the "don't overengineer" scope; the
# client polls GET .../jobs/{id} to watch status change.


def _get_owned_job(job_id: str, user: User):
    try:
        return jobs.get_owned_build_job(job_id, user.id)
    except jobs.BuildJobNotFoundError as e:
        raise HTTPException(status_code=404, detail='Build job not found.') from e
    except jobs.BuildJobAccessError as e:
        raise HTTPException(status_code=403, detail='You do not have access to this build job.') from e


async def _run_build_job_background(build_agent: BuildAgent, job_id: str, task: str, project_type: str) -> None:
    try:
        await build_agent.run(job_id=job_id, task=task, project_type=project_type)
    except Exception:
        # BuildAgent.run already catches its own errors and records
        # FAILED on the job -- this is a last-resort backstop so a
        # genuinely unexpected bug still leaves the job in a terminal
        # state instead of stuck PENDING/GENERATING_FILES forever, and
        # never leaks a stack trace to the client (there's no request
        # to respond to at this point anyway -- this runs after the
        # response was already sent).
        logger.exception('Unexpected error running build job %s in the background.', job_id)
        jobs.update_build_job_status(
            job_id, jobs.FAILED, error='An unexpected error occurred during the build.'
        )


@router.post('/jobs', response_model=BuildJobOut, status_code=202)
async def create_build_job(
    body: BuildJobCreateRequest,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    build_agent: BuildAgent = Depends(get_build_agent),
) -> BuildJobOut:
    if body.conversation_id:
        conversation = db.get(Conversation, body.conversation_id)
        if conversation is None or conversation.user_id != user.id:
            raise HTTPException(status_code=404, detail='Conversation not found.')

    job = jobs.create_build_job(
        user_id=user.id,
        conversation_id=body.conversation_id,
        project_name=body.project_name,
        project_type=body.project_type,
        request_text=body.task,
    )
    background_tasks.add_task(_run_build_job_background, build_agent, job.id, body.task, body.project_type)
    return BuildJobOut.from_job(job)


@router.get('/jobs/by-conversation/{conversation_id}', response_model=BuildJobOut | None)
async def get_latest_job_for_conversation(
    conversation_id: str, user: User = Depends(get_current_user)
) -> BuildJobOut | None:
    """Lets the Flutter Build Workspace panel find "the build this
    conversation is already working on" when a Build-mode conversation
    is reopened, without the client having to remember a job id itself.
    """
    job = jobs.get_latest_build_job_for_conversation(conversation_id)
    if job is None or job.user_id != user.id:
        return None
    return BuildJobOut.from_job(job)


@router.get('/jobs/{job_id}', response_model=BuildJobOut)
async def get_build_job(job_id: str, user: User = Depends(get_current_user)) -> BuildJobOut:
    job = _get_owned_job(job_id, user)
    return BuildJobOut.from_job(job)


@router.get('/jobs/{job_id}/files', response_model=BuildJobFilesResponse)
async def list_build_job_files(
    job_id: str, user: User = Depends(get_current_user), build_agent: BuildAgent = Depends(get_build_agent)
) -> BuildJobFilesResponse:
    _get_owned_job(job_id, user)
    project_dir = build_agent.workspace_path_for(job_id)
    return BuildJobFilesResponse(files=list_workspace_files(project_dir))


@router.get('/jobs/{job_id}/file', response_model=BuildJobFileContentResponse)
async def get_build_job_file(
    job_id: str,
    path: str = Query(min_length=1),
    user: User = Depends(get_current_user),
    build_agent: BuildAgent = Depends(get_build_agent),
) -> BuildJobFileContentResponse:
    """Lets the Flutter file tree show a file's content when clicked --
    same safe_relative_path guard every write tool uses, so a
    ``path`` query param can't read anything outside this job's
    workspace either.
    """
    _get_owned_job(job_id, user)
    project_dir = build_agent.workspace_path_for(job_id)
    try:
        target = safe_relative_path(project_dir, path)
    except BuildWorkspaceError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail=f"'{path}' does not exist in this build.")

    raw_bytes = target.read_bytes()
    try:
        content = raw_bytes.decode('utf-8')
    except UnicodeDecodeError as e:
        raise HTTPException(status_code=415, detail=f"'{path}' is a binary file and can't be displayed.") from e

    if len(raw_bytes) > MAX_FILE_BYTES:
        content = raw_bytes[:MAX_FILE_BYTES].decode('utf-8', errors='ignore')
        content += f'\n\n[... truncated, file is {len(raw_bytes)} bytes, showing first {MAX_FILE_BYTES} ...]'

    return BuildJobFileContentResponse(path=path, content=content)


@router.get('/jobs/{job_id}/artifact')
async def download_build_job_artifact(
    job_id: str, user: User = Depends(get_current_user_allow_query_token)
) -> FileResponse:
    """The one Build endpoint reachable via a plain browser navigation
    (Flutter's "Download ZIP" opens this URL directly rather than
    fetching it) -- see get_current_user_allow_query_token's docstring
    for why it accepts ?token= as well as the usual header.
    """
    job = _get_owned_job(job_id, user)
    if not job.artifact_path or not Path(job.artifact_path).exists():
        raise HTTPException(status_code=404, detail='No downloadable artifact for this build yet.')
    return FileResponse(
        job.artifact_path,
        media_type='application/zip',
        filename=f'{job.project_name}.zip',
    )
