"""Tests for Build mode's DeepCode integration.

Unit tests exercise DeepCodeService directly, with
asyncio.create_subprocess_exec monkeypatched to a fake process — no
real DeepCode/Ollama call, fast and deterministic, matches how
test_chat.py etc. avoid real network/LLM calls via MockAIProvider.
API-level tests hit POST /api/build/run through the FastAPI TestClient
with the service dependency overridden, the same pattern conftest.py's
`client` fixture already uses for get_ai_provider.
"""

import asyncio
import dataclasses
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.build import get_build_agent, get_deepcode_service
from app.core.config import get_settings
from app.main import app
from app.services import build_job_service as jobs
from app.services.build_agent import BuildAgent as BuildAgentClass
from app.services.build_agent import BuildAgentResult
from app.services.build_agent import list_workspace_files as build_workspace_files
from app.services.build_tools import make_build_project_tool, make_check_build_progress_tool
from app.services.build_workspace import BuildWorkspaceConfigError
from app.services.deepcode_service import (
    DeepCodeConfigError,
    DeepCodeRunResult,
    DeepCodeService,
    DeepCodeServiceError,
    validate_project_id,
)


# --- validate_project_id -----------------------------------------------


@pytest.mark.parametrize('name', ['my-app', 'MyApp2', 'a', 'a' * 64, 'todo_list_1'])
def test_accepts_safe_project_ids(name):
    assert validate_project_id(name) == name


@pytest.mark.parametrize(
    'name',
    [
        '',
        '..',
        '../evil',
        'has spaces',
        'has/slash',
        'has\\backslash',
        '.hidden',
        'a' * 65,  # too long
        'semi;colon',
        '$(rm -rf /)',
    ],
)
def test_rejects_unsafe_project_ids(name):
    with pytest.raises(DeepCodeServiceError):
        validate_project_id(name)


# --- workspace root safety ----------------------------------------------


def test_refuses_workspace_root_inside_sana_backend():
    sana_backend_dir = Path(__file__).resolve().parents[1]
    bad_settings = get_settings().model_copy(update={'build_workspaces_root': str(sana_backend_dir)})
    with pytest.raises(DeepCodeConfigError):
        DeepCodeService(settings=bad_settings)


def test_refuses_workspace_root_inside_sana_app():
    sana_app_dir = Path(__file__).resolve().parents[2] / 'sana_app'
    bad_settings = get_settings().model_copy(update={'build_workspaces_root': str(sana_app_dir)})
    with pytest.raises(DeepCodeConfigError):
        DeepCodeService(settings=bad_settings)


def test_accepts_a_safe_workspace_root(tmp_path):
    good_settings = get_settings().model_copy(update={'build_workspaces_root': str(tmp_path / 'sana-builds')})
    service = DeepCodeService(settings=good_settings)
    assert service._workspaces_root == (tmp_path / 'sana-builds').resolve()


# --- DeepCodeService.run_task, with a fake subprocess --------------------


class _FakeProcess:
    def __init__(self, returncode: int, stdout: bytes, stderr: bytes, hang: bool = False):
        self.returncode = returncode
        self._stdout = stdout
        self._stderr = stderr
        self._hang = hang
        self.killed = False

    async def communicate(self):
        if self._hang:
            # Never resolves within the test's short timeout -- exercises
            # the timeout/kill path.
            await asyncio.sleep(3600)
        return self._stdout, self._stderr

    def kill(self):
        self.killed = True

    async def wait(self):
        return self.returncode


@pytest.fixture()
def build_service(tmp_path):
    settings = get_settings().model_copy(update={'build_workspaces_root': str(tmp_path / 'sana-builds')})
    return DeepCodeService(settings=settings)


async def test_run_task_reports_completed_and_lists_generated_files(build_service, monkeypatch):
    workspace_holder = {}

    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        # Simulate DeepCode actually writing a file, the way a real
        # successful run would -- lets the test assert `files` reflects
        # the real post-run workspace contents, not just the exit code.
        workspace_holder['path'] = cwd
        Path(cwd, 'app.py').write_text('print("hi")')
        return _FakeProcess(returncode=0, stdout=b'ok', stderr=b'')

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)

    result = await build_service.run_task(project_id='demo-app', task='make a hello world app')

    assert result.project_id == 'demo-app'
    assert result.status == 'completed'
    assert result.return_code == 0
    assert result.files == ['app.py']
    assert result.workspace_path == str(workspace_holder['path'])


async def test_run_task_does_not_count_deepcodes_own_log_as_a_generated_file(build_service, monkeypatch):
    """Regression test: a live run against the real DeepCode CLI showed
    it writes logs/llm.jsonl on *every* invocation, including ones that
    produce nothing else -- confirmed by directly inspecting the
    workspace after a real call. Without this exclusion, `files` is
    never actually empty, which silently broke the "was anything real
    built" honesty check downstream (build_project's tool response).
    """

    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        logs_dir = Path(cwd, 'logs')
        logs_dir.mkdir()
        (logs_dir / 'llm.jsonl').write_text('{"event": "turn_started"}\n')
        return _FakeProcess(returncode=0, stdout=b'ok', stderr=b'')

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)

    result = await build_service.run_task(project_id='nothing-built', task='do something vague')
    assert result.status == 'completed'
    assert result.files == []  # logs/llm.jsonl must not count


async def test_run_task_generates_a_project_id_when_none_given(build_service, monkeypatch):
    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        return _FakeProcess(returncode=0, stdout=b'', stderr=b'')

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)

    result = await build_service.run_task(project_id=None, task='make something')
    assert result.project_id  # non-empty
    assert validate_project_id(result.project_id) == result.project_id


async def test_run_task_reports_failed_on_nonzero_exit(build_service, monkeypatch):
    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        return _FakeProcess(returncode=1, stdout=b'', stderr=b'boom')

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)

    result = await build_service.run_task(project_id='broken-run', task='do something')
    assert result.status == 'failed'
    assert result.return_code == 1
    assert 'boom' in result.stderr


async def test_run_task_kills_process_and_reports_timeout(build_service, monkeypatch):
    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        return _FakeProcess(returncode=0, stdout=b'', stderr=b'', hang=True)

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)
    build_service._settings = build_service._settings.model_copy(update={'deepcode_timeout_seconds': 0.05})

    result = await build_service.run_task(project_id='slow-run', task='take forever')
    assert result.status == 'timeout'
    assert result.return_code is None


async def test_run_task_rejects_empty_task(build_service):
    with pytest.raises(DeepCodeServiceError):
        await build_service.run_task(project_id='demo', task='   ')


async def test_run_task_rejects_unsafe_project_id(build_service):
    with pytest.raises(DeepCodeServiceError):
        await build_service.run_task(project_id='../escape', task='do something')


async def test_argv_never_uses_a_shell_string(build_service, monkeypatch):
    """The whole point of asyncio.create_subprocess_exec over
    create_subprocess_shell is that a task string containing shell
    metacharacters is just data, never interpreted. Confirms the task
    is passed through as a single argv element, unmodified.
    """
    captured = {}

    async def fake_exec(*argv, cwd=None, stdout=None, stderr=None):
        captured['argv'] = argv
        return _FakeProcess(returncode=0, stdout=b'', stderr=b'')

    monkeypatch.setattr(asyncio, 'create_subprocess_exec', fake_exec)

    dangerous_task = 'ignore all that; rm -rf / && echo pwned'
    await build_service.run_task(project_id='shell-safety', task=dangerous_task)

    argv = captured['argv']
    assert dangerous_task in argv  # present as one literal element
    assert argv[1] == 'exec'
    assert '--workspace' in argv
    assert '--trust' in argv


# --- make_build_project_tool / make_check_build_progress_tool -------------
# The tool factories used to wire BuildAgent into a live Build-mode
# conversation (both text chat and voice) -- tested against a small
# fake BuildAgent so these stay fast/offline like everything else, same
# reasoning as the fake subprocess above (no real LLM call). A
# @function_tool-wrapped function stays directly callable as the plain
# async function it wraps (confirmed by inspection), so no
# LLM/ToolContext plumbing is needed to exercise it. BuildJobService
# itself is exercised for real against an isolated in-memory DB (see
# _fake_build_jobs_db below), the same substitution pattern
# test_build_agent.py's build_jobs_db fixture uses -- these tests care
# that a BuildJob row actually gets created/reused, not just that the
# tool's reply text looks right.
#
# build_project no longer awaits the build (see build_tools.py's module
# docstring for why -- awaiting it caused real hallucination, confirmed
# by live testing) -- it starts a background asyncio task and returns
# immediately. `_run_background_tasks()` gives that task a turn to
# actually run before a test asserts on its effects, the same thing a
# real event loop does naturally between conversation turns.


async def _run_background_tasks() -> None:
    await asyncio.sleep(0)
    await asyncio.sleep(0)


class _FakeBuildAgent:
    def __init__(self, result: BuildAgentResult | None = None, error: Exception | None = None):
        self._result = result
        self._error = error
        self.calls: list[str] = []

    async def run(self, *, job_id, task, project_type):
        self.calls.append(job_id)
        if self._error:
            raise self._error
        result = dataclasses.replace(self._result, job_id=job_id)
        # Mirrors what the real BuildAgent does at the end of a run --
        # check_build_progress reads status from the DB, not from this
        # fake's return value (build_project never sees it either, now
        # that nothing awaits run() directly).
        jobs.update_build_job_status(job_id, result.status, error=result.error)
        if result.artifact_path:
            jobs.set_build_job_artifact(job_id, result.artifact_path)
        return result


def _result(**overrides):
    defaults = dict(
        job_id='job-1',
        status=jobs.COMPLETED,
        files=['manifest.json', 'popup.js'],
        workspace_path='/fake/job-1',
        artifact_path=None,
        error=None,
    )
    defaults.update(overrides)
    return BuildAgentResult(**defaults)


@pytest.fixture()
def fake_build_jobs_db(monkeypatch):
    """Points build_job_service's SessionLocal at a throwaway in-memory
    DB for the duration of one test, and seeds one real User row --
    same substitution test_build_agent.py's build_jobs_db fixture uses.
    """
    from app.db.session import Base
    from app.models.user import User

    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    monkeypatch.setattr(jobs, 'SessionLocal', TestSessionLocal)

    session = TestSessionLocal()
    user = User(email='tool-builder@example.com', password_hash='x')
    session.add(user)
    session.commit()
    session.refresh(user)
    session.close()

    yield user.id

    Base.metadata.drop_all(bind=engine)


async def test_build_project_tool_returns_immediately_without_claiming_completion(fake_build_jobs_db):
    """The core honesty fix: build_project must never claim the build is
    done, since it never waits to find out -- confirmed by live testing
    that awaiting the real thing let a slow build get claimed "finished"
    while it was still running minutes later.
    """
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result(files=['main.py', 'app.py']))
    tool = make_build_project_tool(fake, {'job_id': None}, user_id=user_id, conversation_id=None)

    reply = await tool(task='make a todo app', project_name='p', project_type='web_app')
    assert 'started' in reply.lower()
    assert 'check_build_progress' in reply
    # Must not make a positive completion claim -- "do not say it's
    # finished" (an instruction *to the model*) is fine and expected;
    # "build completed"/"is ready" (a claim) is exactly what must never
    # appear here, since nothing has actually finished yet.
    for phrase in ('build completed', 'is ready', 'is done', 'has finished'):
        assert phrase not in reply.lower()


async def test_build_project_tool_seeds_and_then_reuses_job_id(fake_build_jobs_db):
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result())
    holder = {'job_id': 'seeded-id'}
    tool = make_build_project_tool(fake, holder, user_id=user_id, conversation_id='seeded-id')

    await tool(task='make a todo app', project_name='TodoApp', project_type='web_app')
    await tool(task='now add a delete button', project_name='TodoApp', project_type='web_app')
    await _run_background_tasks()

    # Seeded id used both times -- text chat's case, where job_id is
    # deterministically the conversation_id from the very first call.
    assert fake.calls == ['seeded-id', 'seeded-id']
    # And a BuildJob row was actually created for it (not just echoed
    # back in a fake result) -- exactly one, reused on the second call.
    job = jobs.get_build_job('seeded-id')
    assert job is not None
    assert job.user_id == user_id


async def test_build_project_tool_mints_id_on_first_call_then_reuses_it(fake_build_jobs_db):
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result(job_id='auto-minted'))
    holder = {'job_id': None}
    tool = make_build_project_tool(fake, holder, user_id=user_id, conversation_id=None)

    await tool(task='make a todo app', project_name='TodoApp', project_type='web_app')
    minted_id = holder['job_id']
    assert minted_id

    await tool(task='now add a delete button', project_name='TodoApp', project_type='web_app')
    await _run_background_tasks()
    # Second call reuses what the first call's result populated --
    # voice's case, where nothing is known before the first build.
    assert fake.calls == [minted_id, minted_id]
    assert jobs.get_build_job(minted_id) is not None


async def test_build_project_tool_works_with_no_user_id_but_is_untracked(fake_build_jobs_db):
    """No user_id (an old voice client that never sent one) still
    builds -- it just can't be looked up via the API afterward.
    """
    fake = _FakeBuildAgent(result=_result())
    holder = {'job_id': None}
    tool = make_build_project_tool(fake, holder, user_id=None, conversation_id=None)

    reply = await tool(task='make a todo app', project_name='TodoApp', project_type='web_app')
    assert 'started' in reply.lower()
    assert holder['job_id']  # a workspace id was still minted
    assert jobs.get_build_job(holder['job_id']) is None  # but no trackable row


async def test_build_project_tool_handles_get_or_create_job_error_without_raising(fake_build_jobs_db, monkeypatch):
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result())
    tool = make_build_project_tool(fake, {'job_id': None}, user_id=user_id, conversation_id=None)

    def _boom(*a, **k):
        raise RuntimeError('db is down')

    monkeypatch.setattr(jobs, 'create_build_job', _boom)

    reply = await tool(task='make a todo app', project_name='p', project_type='web_app')  # must not raise
    assert "couldn't start the build" in reply.lower()


# --- make_check_build_progress_tool -----------------------------------------
# check_build_progress is the *only* honest source of "is it done yet"
# now that build_project itself never waits -- these tests drive a
# build through the fake agent and confirm each stage is reported
# accurately, including failure.


async def test_check_build_progress_before_any_build_started(fake_build_jobs_db):
    tool = make_check_build_progress_tool(_FakeBuildAgent(result=_result()), {'job_id': None})
    reply = await tool()
    assert 'no build has been started' in reply.lower()


async def test_check_build_progress_reports_completion_honestly(fake_build_jobs_db):
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result(files=['main.py', 'app.py']))
    holder = {'job_id': None}
    build_tool = make_build_project_tool(fake, holder, user_id=user_id, conversation_id=None)
    progress_tool = make_check_build_progress_tool(fake, holder)

    await build_tool(task='make a todo app', project_name='p', project_type='web_app')
    await _run_background_tasks()

    reply = await progress_tool()
    assert 'complete' in reply.lower()


async def test_check_build_progress_reports_failure_honestly(fake_build_jobs_db):
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(result=_result(status=jobs.FAILED, error='no files were created'))
    holder = {'job_id': None}
    build_tool = make_build_project_tool(fake, holder, user_id=user_id, conversation_id=None)
    progress_tool = make_check_build_progress_tool(fake, holder)

    await build_tool(task='make a todo app', project_name='p', project_type='web_app')
    await _run_background_tasks()

    reply = await progress_tool()
    assert 'failed' in reply.lower()
    assert 'no files were created' in reply


async def test_check_build_progress_survives_an_unexpected_background_error(fake_build_jobs_db):
    """Mirrors the real BuildAgent.run raising unexpectedly mid-build --
    the background handler must still leave the job in a terminal
    (FAILED) state, not stuck PENDING forever with no honest answer.
    """
    user_id = fake_build_jobs_db
    fake = _FakeBuildAgent(error=BuildWorkspaceConfigError('misconfigured'))
    holder = {'job_id': None}
    build_tool = make_build_project_tool(fake, holder, user_id=user_id, conversation_id=None)
    progress_tool = make_check_build_progress_tool(fake, holder)

    await build_tool(task='make a todo app', project_name='p', project_type='web_app')  # must not raise
    await _run_background_tasks()

    reply = await progress_tool()
    assert 'failed' in reply.lower()


# --- API layer ------------------------------------------------------------


class _StubDeepCodeService:
    async def run_task(self, *, project_id, task):
        from app.services.deepcode_service import DeepCodeRunResult

        return DeepCodeRunResult(
            project_id=project_id or 'stub-project',
            status='completed',
            return_code=0,
            stdout='stub stdout',
            stderr='',
            workspace_path='/fake/workspace',
            files=['main.py'],
        )


@pytest.fixture()
def client_with_stub_deepcode(client: TestClient):
    app.dependency_overrides[get_deepcode_service] = lambda: _StubDeepCodeService()
    yield client
    del app.dependency_overrides[get_deepcode_service]


@pytest.fixture()
def client_with_real_tmp_deepcode(client: TestClient, tmp_path):
    # A *real* DeepCodeService (real validation logic), just pointed at
    # a throwaway tmp_path workspace root instead of the default
    # sana-builds/ — so this never touches the real filesystem sibling
    # directory, only what pytest's tmp_path already cleans up.
    settings = get_settings().model_copy(update={'build_workspaces_root': str(tmp_path / 'sana-builds')})
    app.dependency_overrides[get_deepcode_service] = lambda: DeepCodeService(settings=settings)
    yield client
    del app.dependency_overrides[get_deepcode_service]


def test_run_build_requires_auth(client: TestClient):
    resp = client.post('/api/build/run', json={'task': 'make an app'})
    assert resp.status_code == 401


def test_run_build_returns_result(client_with_stub_deepcode, register_and_login):
    _, headers = register_and_login('builder@example.com')
    resp = client_with_stub_deepcode.post(
        '/api/build/run', json={'task': 'make a todo app'}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body['status'] == 'completed'
    assert body['files'] == ['main.py']
    assert body['project_id'] == 'stub-project'


def test_run_build_rejects_empty_task(client_with_stub_deepcode, register_and_login):
    _, headers = register_and_login('builder2@example.com')
    resp = client_with_stub_deepcode.post('/api/build/run', json={'task': ''}, headers=headers)
    assert resp.status_code == 422  # Pydantic min_length validation


def test_run_build_rejects_bad_project_id(client_with_real_tmp_deepcode, register_and_login):
    _, headers = register_and_login('builder3@example.com')
    resp = client_with_real_tmp_deepcode.post(
        '/api/build/run',
        json={'project_id': '../escape', 'task': 'make an app'},
        headers=headers,
    )
    assert resp.status_code == 400


# --- BuildJob API (BuildAgent) ----------------------------------------------
# build_job_service.py self-manages its own SessionLocal (see its
# module docstring) rather than taking FastAPI's request-scoped
# Session, so it isn't automatically covered by the `client` fixture's
# get_db override -- these tests repoint it at the *same* underlying
# engine `client` already uses, so a User created via /auth/register
# through the normal HTTP flow is visible to build_job_service too.
# BuildAgent.run itself is stubbed (subclassing the real one so
# workspace/zip/status-update logic stays real) to avoid any actual
# LLM call -- consistent with client_with_stub_deepcode's approach above.


class _StubBuildAgent(BuildAgentClass):
    async def run(self, *, job_id, task, project_type):
        jobs.update_build_job_status(job_id, jobs.GENERATING_FILES)
        project_dir = self.workspace_path_for(job_id)
        project_dir.mkdir(parents=True, exist_ok=True)
        (project_dir / 'index.html').write_text('<html>stub</html>', encoding='utf-8')
        jobs.update_build_job_status(job_id, jobs.PACKAGING)
        artifact_path = self._zip_project(job_id, project_dir)
        jobs.set_build_job_artifact(job_id, str(artifact_path))
        jobs.update_build_job_status(job_id, jobs.COMPLETED)
        return BuildAgentResult(
            job_id=job_id,
            status=jobs.COMPLETED,
            files=build_workspace_files(project_dir),
            workspace_path=str(project_dir),
            artifact_path=str(artifact_path),
        )


@pytest.fixture()
def client_with_build_jobs(client: TestClient, db_session, tmp_path, monkeypatch):
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=db_session.get_bind())
    monkeypatch.setattr(jobs, 'SessionLocal', TestSessionLocal)

    settings = get_settings().model_copy(update={'build_workspaces_root': str(tmp_path / 'sana-builds')})
    stub_agent = _StubBuildAgent(settings=settings)
    app.dependency_overrides[get_build_agent] = lambda: stub_agent
    yield client
    del app.dependency_overrides[get_build_agent]


def test_create_build_job_requires_auth(client: TestClient):
    resp = client.post('/api/build/jobs', json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app'})
    assert resp.status_code == 401


def test_create_build_job_rejects_bad_project_type(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobtype@example.com')
    resp = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'not-a-real-type'},
        headers=headers,
    )
    assert resp.status_code == 422


def test_create_build_job_runs_to_completion_and_is_gettable(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobrun@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'block a domain', 'project_name': 'FocusBlock', 'project_type': 'chrome_extension'},
        headers=headers,
    )
    assert created.status_code == 202, created.text
    job_id = created.json()['id']
    assert created.json()['project_name'] == 'FocusBlock'

    # TestClient drives the background task to completion before the
    # POST call above even returns (Starlette awaits it as part of
    # sending the response) -- so this should already show COMPLETED.
    got = client_with_build_jobs.get(f'/api/build/jobs/{job_id}', headers=headers)
    assert got.status_code == 200
    body = got.json()
    assert body['status'] == 'COMPLETED'
    assert body['has_artifact'] is True


def test_get_build_job_rejects_other_users_job(client_with_build_jobs, register_and_login):
    _, headers_a = register_and_login('joba@example.com')
    _, headers_b = register_and_login('jobb@example.com')

    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app'},
        headers=headers_a,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}', headers=headers_b)
    assert resp.status_code == 403


def test_get_build_job_404_for_unknown_id(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobmissing@example.com')
    resp = client_with_build_jobs.get('/api/build/jobs/does-not-exist', headers=headers)
    assert resp.status_code == 404


def test_list_build_job_files_after_completion(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobfiles@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}/files', headers=headers)
    assert resp.status_code == 200
    assert resp.json()['files'] == ['index.html']


def test_get_build_job_file_content(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobfilecontent@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}/file', params={'path': 'index.html'}, headers=headers)
    assert resp.status_code == 200
    assert resp.json()['content'] == '<html>stub</html>'


def test_get_build_job_file_rejects_path_traversal(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobfiletraversal@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(
        f'/api/build/jobs/{job_id}/file', params={'path': '../../evil.txt'}, headers=headers
    )
    assert resp.status_code == 400


def test_download_build_job_artifact(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobartifact@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'FocusBlock', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}/artifact', headers=headers)
    assert resp.status_code == 200
    assert resp.headers['content-type'] == 'application/zip'
    assert 'FocusBlock.zip' in resp.headers['content-disposition']


def test_download_build_job_artifact_accepts_query_token_with_no_header(client_with_build_jobs, register_and_login):
    """The Flutter "Download ZIP" button opens this URL directly (a
    plain browser navigation, not a fetch with headers) -- confirms the
    ?token= fallback (get_current_user_allow_query_token) actually works.
    """
    _, headers = register_and_login('jobartifacttoken@example.com')
    token = headers['Authorization'].removeprefix('Bearer ')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'FocusBlock', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}/artifact', params={'token': token})
    assert resp.status_code == 200
    assert resp.headers['content-type'] == 'application/zip'


def test_download_build_job_artifact_rejects_no_auth_at_all(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobartifactnoauth@example.com')
    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'FocusBlock', 'project_type': 'web_app'},
        headers=headers,
    )
    job_id = created.json()['id']

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job_id}/artifact')
    assert resp.status_code == 401


def test_download_build_job_artifact_404_before_it_exists(client_with_build_jobs, register_and_login):
    """The stub agent above always finishes (and sets an artifact)
    synchronously, so exercising "no artifact yet" means going around
    it and creating a bare BuildJob row directly via the service layer
    -- the same state a job sits in for real between PENDING and
    PACKAGING.
    """
    user, headers = register_and_login('jobartifactmissing@example.com')
    job = jobs.create_build_job(
        user_id=user['id'],
        conversation_id=None,
        project_name='p',
        project_type='web_app',
        request_text='x',
    )

    resp = client_with_build_jobs.get(f'/api/build/jobs/{job.id}/artifact', headers=headers)
    assert resp.status_code == 404


def test_get_latest_job_for_conversation_returns_null_when_none(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobconvo@example.com')
    resp = client_with_build_jobs.get(
        '/api/build/jobs/by-conversation/00000000-0000-0000-0000-000000000000', headers=headers
    )
    assert resp.status_code == 200
    assert resp.json() is None


def test_create_build_job_with_conversation_id_links_it(client_with_build_jobs, register_and_login):
    _, headers = register_and_login('jobconvolink@example.com')
    convo = client_with_build_jobs.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'build', 'message': 'hi'},
        headers=headers,
    )
    conversation_id = convo.json()['conversation_id']

    created = client_with_build_jobs.post(
        '/api/build/jobs',
        json={
            'task': 'x',
            'project_name': 'p',
            'project_type': 'web_app',
            'conversation_id': conversation_id,
        },
        headers=headers,
    )
    assert created.status_code == 202, created.text

    latest = client_with_build_jobs.get(f'/api/build/jobs/by-conversation/{conversation_id}', headers=headers)
    assert latest.status_code == 200
    assert latest.json()['id'] == created.json()['id']


def test_create_build_job_rejects_conversation_id_owned_by_someone_else(client_with_build_jobs, register_and_login):
    _, headers_a = register_and_login('convoowner@example.com')
    _, headers_b = register_and_login('notconvoowner@example.com')

    convo = client_with_build_jobs.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'build', 'message': 'hi'},
        headers=headers_a,
    )
    conversation_id = convo.json()['conversation_id']

    resp = client_with_build_jobs.post(
        '/api/build/jobs',
        json={'task': 'x', 'project_name': 'p', 'project_type': 'web_app', 'conversation_id': conversation_id},
        headers=headers_b,
    )
    assert resp.status_code == 404
