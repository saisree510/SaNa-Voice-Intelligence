"""BuildJob persistence — status tracking for the Build Agent pipeline
(app/services/build_agent.py), queried by the REST endpoints
(app/api/build.py) and written to from inside the build_project tool's
closure (app/services/build_tools.py).

Free functions that each open and close their own short-lived
[SessionLocal], the same pattern voice_transcript_service.py already
uses — not a FastAPI request-scoped Session, because this needs to be
callable from a tool-calling closure mid-conversation just as much as
from a route handler, and BuildJob has no relationships to lazy-load
after the session closes, so a detached instance is safe to read.
"""

import logging

from ..db.session import SessionLocal
from ..models.build_job import BuildJob

logger = logging.getLogger('sana-backend')

# Mirrors BuildJob.status's documented value set (models/build_job.py).
PENDING = 'PENDING'
PLANNING = 'PLANNING'
CREATING_WORKSPACE = 'CREATING_WORKSPACE'
GENERATING_FILES = 'GENERATING_FILES'
VALIDATING = 'VALIDATING'
FIXING = 'FIXING'
PACKAGING = 'PACKAGING'
COMPLETED = 'COMPLETED'
FAILED = 'FAILED'


class BuildJobNotFoundError(LookupError):
    pass


class BuildJobAccessError(PermissionError):
    pass


def create_build_job(
    *,
    user_id: str,
    conversation_id: str | None,
    project_name: str,
    project_type: str,
    request_text: str,
    job_id: str | None = None,
) -> BuildJob:
    """[job_id] lets a caller pre-decide the id (the conversational tool
    uses conversation_id as both the BuildJob id and the workspace
    project id, so there's one id for "this project", not two) --
    omitted, the column default (a fresh uuid4) applies.
    """
    db = SessionLocal()
    try:
        kwargs = {
            'user_id': user_id,
            'conversation_id': conversation_id,
            'project_name': project_name,
            'project_type': project_type,
            'request': request_text,
            'status': PENDING,
        }
        if job_id:
            kwargs['id'] = job_id
        job = BuildJob(**kwargs)
        db.add(job)
        db.commit()
        db.refresh(job)
        return job
    finally:
        db.close()


def update_build_job_status(job_id: str, status: str, *, error: str | None = None) -> None:
    db = SessionLocal()
    try:
        job = db.get(BuildJob, job_id)
        if job is None:
            logger.warning('update_build_job_status: job %s not found.', job_id)
            return
        job.status = status
        if error is not None:
            job.error = error
        db.commit()
    finally:
        db.close()


def set_build_job_artifact(job_id: str, artifact_path: str) -> None:
    db = SessionLocal()
    try:
        job = db.get(BuildJob, job_id)
        if job is None:
            logger.warning('set_build_job_artifact: job %s not found.', job_id)
            return
        job.artifact_path = artifact_path
        db.commit()
    finally:
        db.close()


def get_build_job(job_id: str) -> BuildJob | None:
    db = SessionLocal()
    try:
        return db.get(BuildJob, job_id)
    finally:
        db.close()


def get_owned_build_job(job_id: str, user_id: str) -> BuildJob:
    job = get_build_job(job_id)
    if job is None:
        raise BuildJobNotFoundError(f'Build job {job_id} not found.')
    if job.user_id != user_id:
        raise BuildJobAccessError('You do not have access to this build job.')
    return job


def get_latest_build_job_for_conversation(conversation_id: str) -> BuildJob | None:
    db = SessionLocal()
    try:
        return (
            db.query(BuildJob)
            .filter(BuildJob.conversation_id == conversation_id)
            .order_by(BuildJob.created_at.desc())
            .first()
        )
    finally:
        db.close()
