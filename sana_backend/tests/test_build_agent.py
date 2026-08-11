"""Tests for the native BuildAgent: file tools, path-traversal safety,
Chrome Manifest V3 validation, ZIP packaging, and BuildJobService CRUD.

No real LLM call anywhere in this file — the file tools are plain
async functions (a @function_tool wraps but doesn't hide the callable,
same pattern test_build.py's tool tests already rely on), found by
`.info.name` since _make_file_tools returns them as a list. BuildAgent
.run's actual generation loop (which does call inference.LLM) is
exercised indirectly in test_build.py's make_build_project_tool tests,
via a fake BuildAgent — not a real network call there either.
"""

import json
import zipfile
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base
from app.models.user import User
from app.services import build_job_service as jobs
from app.services.build_agent import BuildAgent, _make_file_tools, list_workspace_files
from app.services.build_validation import validate_chrome_extension
from app.services.build_workspace import BuildWorkspaceError, safe_relative_path


def _tool(tools, name):
    return next(t for t in tools if t.info.name == name)


# --- safe_relative_path (the guard every file tool routes through) ------


@pytest.mark.parametrize(
    'bad_path',
    ['../escape', '../../etc/passwd', 'C:\\Windows\\system32', '..', '', '   '],
)
def test_safe_relative_path_rejects_traversal(tmp_path, bad_path):
    project_dir = tmp_path / 'proj'
    project_dir.mkdir()
    with pytest.raises(BuildWorkspaceError):
        safe_relative_path(project_dir, bad_path)


def test_safe_relative_path_accepts_nested_path(tmp_path):
    project_dir = tmp_path / 'proj'
    project_dir.mkdir()
    resolved = safe_relative_path(project_dir, 'src/popup.js')
    assert resolved == (project_dir / 'src' / 'popup.js').resolve()


def test_safe_relative_path_treats_leading_slash_as_project_relative(tmp_path):
    """A leading '/' is stripped, not treated as filesystem-root -- the
    same convention Chrome manifest paths use (a leading '/' means
    "relative to the extension root", not an escape). Confirms this
    lands *inside* the project, not at a real /etc/passwd.
    """
    project_dir = tmp_path / 'proj'
    project_dir.mkdir()
    resolved = safe_relative_path(project_dir, '/etc/passwd')
    resolved.relative_to(project_dir.resolve())  # raises if it escaped


# --- file tools -----------------------------------------------------------


@pytest.fixture()
def project_dir(tmp_path):
    d = tmp_path / 'proj'
    d.mkdir()
    return d


async def test_create_file_writes_a_real_file(project_dir):
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'create_file')(path='manifest.json', content='{"a": 1}')
    assert 'Created' in reply
    assert (project_dir / 'manifest.json').read_text(encoding='utf-8') == '{"a": 1}'


async def test_create_file_creates_missing_parent_dirs(project_dir):
    tools = _make_file_tools(project_dir)
    await _tool(tools, 'create_file')(path='src/popup/popup.js', content='console.log(1)')
    assert (project_dir / 'src' / 'popup' / 'popup.js').exists()


async def test_create_file_rejects_path_traversal(project_dir):
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'create_file')(path='../../evil.txt', content='pwned')
    assert reply.startswith('Error:')
    assert not (project_dir.parent.parent / 'evil.txt').exists()


async def test_create_file_rejects_absolute_path(project_dir):
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'create_file')(path='C:\\Windows\\evil.txt', content='pwned')
    assert reply.startswith('Error:')


async def test_read_file_returns_content(project_dir):
    (project_dir / 'a.txt').write_text('hello', encoding='utf-8')
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'read_file')(path='a.txt')
    assert reply == 'hello'


async def test_read_file_missing_reports_error_not_crash(project_dir):
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'read_file')(path='missing.txt')
    assert 'Error' in reply


async def test_update_file_replaces_content(project_dir):
    (project_dir / 'a.txt').write_text('old', encoding='utf-8')
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'update_file')(path='a.txt', content='new')
    assert 'Updated' in reply
    assert (project_dir / 'a.txt').read_text(encoding='utf-8') == 'new'


async def test_list_files_lists_project_root(project_dir):
    (project_dir / 'a.txt').write_text('x', encoding='utf-8')
    (project_dir / 'sub').mkdir()
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'list_files')(path='')
    assert 'a.txt' in reply
    assert 'sub/' in reply


async def test_delete_file_removes_it(project_dir):
    (project_dir / 'a.txt').write_text('x', encoding='utf-8')
    tools = _make_file_tools(project_dir)
    reply = await _tool(tools, 'delete_file')(path='a.txt')
    assert 'Deleted' in reply
    assert not (project_dir / 'a.txt').exists()


async def test_create_directory_makes_nested_dirs(project_dir):
    tools = _make_file_tools(project_dir)
    await _tool(tools, 'create_directory')(path='icons/large')
    assert (project_dir / 'icons' / 'large').is_dir()


def test_list_workspace_files_ignores_directories(project_dir):
    (project_dir / 'a.txt').write_text('x', encoding='utf-8')
    (project_dir / 'sub').mkdir()
    (project_dir / 'sub' / 'b.txt').write_text('y', encoding='utf-8')
    assert list_workspace_files(project_dir) == ['a.txt', 'sub/b.txt']


# --- Chrome Manifest V3 validation ----------------------------------------


def _valid_manifest_project(project_dir: Path) -> None:
    (project_dir / 'popup.html').write_text('<html></html>', encoding='utf-8')
    (project_dir / 'popup.js').write_text('', encoding='utf-8')
    (project_dir / 'background.js').write_text('', encoding='utf-8')
    manifest = {
        'manifest_version': 3,
        'name': 'FocusBlock',
        'version': '1.0',
        'action': {'default_popup': 'popup.html'},
        'background': {'service_worker': 'background.js'},
        'permissions': ['storage'],
    }
    (project_dir / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')


def test_valid_manifest_passes(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    _valid_manifest_project(project_dir)
    assert validate_chrome_extension(project_dir) == []


def test_missing_manifest_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    errors = validate_chrome_extension(project_dir)
    assert any('manifest.json is missing' in e for e in errors)


def test_invalid_json_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    (project_dir / 'manifest.json').write_text('{not valid json', encoding='utf-8')
    errors = validate_chrome_extension(project_dir)
    assert any('not valid JSON' in e for e in errors)


def test_wrong_manifest_version_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    (project_dir / 'manifest.json').write_text(
        json.dumps({'manifest_version': 2, 'name': 'x', 'version': '1'}), encoding='utf-8'
    )
    errors = validate_chrome_extension(project_dir)
    assert any('manifest_version' in e for e in errors)


def test_missing_referenced_popup_file_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    manifest = {
        'manifest_version': 3,
        'name': 'x',
        'version': '1',
        'action': {'default_popup': 'popup.html'},
    }
    (project_dir / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    errors = validate_chrome_extension(project_dir)
    assert any('popup.html' in e and 'does not exist' in e for e in errors)


def test_missing_referenced_background_worker_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    manifest = {
        'manifest_version': 3,
        'name': 'x',
        'version': '1',
        'background': {'service_worker': 'bg.js'},
    }
    (project_dir / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    errors = validate_chrome_extension(project_dir)
    assert any('bg.js' in e and 'does not exist' in e for e in errors)


def test_missing_content_script_file_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    manifest = {
        'manifest_version': 3,
        'name': 'x',
        'version': '1',
        'content_scripts': [{'matches': ['<all_urls>'], 'js': ['content.js']}],
    }
    (project_dir / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    errors = validate_chrome_extension(project_dir)
    assert any('content.js' in e for e in errors)


def test_bad_permissions_shape_is_rejected(tmp_path):
    project_dir = tmp_path / 'ext'
    project_dir.mkdir()
    manifest = {'manifest_version': 3, 'name': 'x', 'version': '1', 'permissions': 'storage'}
    (project_dir / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    errors = validate_chrome_extension(project_dir)
    assert any('permissions' in e for e in errors)


# --- ZIP packaging ----------------------------------------------------------


def test_zip_project_packages_every_generated_file(tmp_path):
    settings = _settings_for(tmp_path)
    agent = BuildAgent(settings=settings)
    project_dir = agent.workspace_path_for('zip-job')
    project_dir.mkdir(parents=True)
    (project_dir / 'manifest.json').write_text('{}', encoding='utf-8')
    (project_dir / 'src').mkdir()
    (project_dir / 'src' / 'popup.js').write_text('1', encoding='utf-8')

    artifact_path = agent._zip_project('zip-job', project_dir)

    assert artifact_path.exists()
    with zipfile.ZipFile(artifact_path) as zf:
        names = set(zf.namelist())
    assert names == {'manifest.json', 'src/popup.js'}


def _settings_for(tmp_path):
    from app.core.config import get_settings

    return get_settings().model_copy(update={'build_workspaces_root': str(tmp_path / 'sana-builds')})


# --- BuildJobService --------------------------------------------------------
# build_job_service.py deliberately self-manages its own short-lived
# SessionLocal() calls (see its module docstring) rather than taking a
# request-scoped Session — so unlike the rest of the suite (which
# overrides FastAPI's get_db dependency), exercising it here means
# monkeypatching its module-level SessionLocal at a fresh, isolated
# in-memory engine, the same substitution app startup does for the
# real one, just pointed at a throwaway database.


@pytest.fixture()
def build_jobs_db(monkeypatch):
    engine = create_engine(
        'sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool
    )
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    monkeypatch.setattr(jobs, 'SessionLocal', TestSessionLocal)

    session = TestSessionLocal()
    user_a = User(email='builder-a@example.com', password_hash='x')
    user_b = User(email='builder-b@example.com', password_hash='x')
    session.add_all([user_a, user_b])
    session.commit()
    session.refresh(user_a)
    session.refresh(user_b)
    session.close()

    yield user_a.id, user_b.id

    Base.metadata.drop_all(bind=engine)


def test_create_and_get_build_job_roundtrips(build_jobs_db):
    user_id, _ = build_jobs_db
    job = jobs.create_build_job(
        user_id=user_id,
        conversation_id=None,
        project_name='FocusBlock',
        project_type='chrome_extension',
        request_text='block a domain',
    )
    fetched = jobs.get_build_job(job.id)
    assert fetched is not None
    assert fetched.status == jobs.PENDING
    assert fetched.project_name == 'FocusBlock'


def test_create_build_job_honors_explicit_job_id(build_jobs_db):
    user_id, _ = build_jobs_db
    job = jobs.create_build_job(
        user_id=user_id,
        conversation_id=None,
        project_name='p',
        project_type='web_app',
        request_text='t',
        job_id='explicit-id-123',
    )
    assert job.id == 'explicit-id-123'
    assert jobs.get_build_job('explicit-id-123') is not None


def test_update_build_job_status_persists(build_jobs_db):
    user_id, _ = build_jobs_db
    job = jobs.create_build_job(
        user_id=user_id, conversation_id=None, project_name='p', project_type='web_app', request_text='t'
    )
    jobs.update_build_job_status(job.id, jobs.GENERATING_FILES)
    assert jobs.get_build_job(job.id).status == jobs.GENERATING_FILES

    jobs.update_build_job_status(job.id, jobs.FAILED, error='boom')
    updated = jobs.get_build_job(job.id)
    assert updated.status == jobs.FAILED
    assert updated.error == 'boom'


def test_update_build_job_status_on_missing_job_does_not_raise(build_jobs_db):
    jobs.update_build_job_status('does-not-exist', jobs.COMPLETED)  # must not raise


def test_set_build_job_artifact_persists(build_jobs_db):
    user_id, _ = build_jobs_db
    job = jobs.create_build_job(
        user_id=user_id, conversation_id=None, project_name='p', project_type='web_app', request_text='t'
    )
    jobs.set_build_job_artifact(job.id, '/fake/path.zip')
    assert jobs.get_build_job(job.id).artifact_path == '/fake/path.zip'


def test_get_owned_build_job_rejects_wrong_user(build_jobs_db):
    user_id, other_user_id = build_jobs_db
    job = jobs.create_build_job(
        user_id=user_id, conversation_id=None, project_name='p', project_type='web_app', request_text='t'
    )
    with pytest.raises(jobs.BuildJobAccessError):
        jobs.get_owned_build_job(job.id, other_user_id)


def test_get_owned_build_job_raises_not_found_for_missing_job(build_jobs_db):
    user_id, _ = build_jobs_db
    with pytest.raises(jobs.BuildJobNotFoundError):
        jobs.get_owned_build_job('does-not-exist', user_id)
