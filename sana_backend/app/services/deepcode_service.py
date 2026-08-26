"""DeepCodeService — SANA Build mode's only connection to DeepCode.

Wraps `deepcode exec` (see .env.example for DEEPCODE_* settings) so a
Build-mode conversation can actually generate a project via a local
DeepCode + Ollama pipeline, instead of only ever discussing one in the
abstract. Deliberately isolated from everything else in the backend:
Debate mode, Brainstorm mode, and the existing /chat/message pipeline
never import or call this.

Safety properties (all load-bearing, not incidental):
- Every generated project lives under a dedicated workspace root
  (BUILD_WORKSPACES_ROOT, default sana-builds/ — a *sibling* of
  sana_app/ and sana_backend/, never inside either) so DeepCode's
  full-access file operations can never reach SANA's own source. The
  service refuses to start if that root ever resolves inside either
  project directory.
- Project ids are strictly validated (see validate_project_id) before
  ever being joined into a filesystem path, and the joined path is
  re-checked against the workspace root afterward — the same
  belt-and-suspenders pattern file_access.py uses for Build mode's
  read-only source-browsing tools.
- The subprocess is started via argv (asyncio.create_subprocess_exec),
  never a shell string — no shell=True, no shell-metacharacter risk
  from a task string or project id.
- A hard timeout: on expiry the process is killed (not just abandoned)
  and its exit is awaited before returning, so a runaway local-model
  call can't leak an orphaned process.
"""

import asyncio
import logging
from dataclasses import dataclass, field
from pathlib import Path

from ..core.config import Settings, get_settings
from .build_workspace import (
    BuildWorkspaceConfigError,
    BuildWorkspaceError,
    new_project_id as _new_project_id,
    project_dir_for,
    resolve_workspaces_root,
)
from .build_workspace import validate_project_id as _shared_validate_project_id

logger = logging.getLogger('sana-backend')

# Output is stored in full in the result object (callers may want it
# for logging), but this caps what a route hands back to a client --
# a runaway model response or a verbose transcript shouldn't blow up
# an API response. Mirrors file_access.py's MAX_FILE_BYTES truncation
# pattern.
MAX_OUTPUT_CHARS = 20_000


class DeepCodeConfigError(RuntimeError):
    """Raised at DeepCodeService construction time for a configuration
    problem serious enough that no run should be attempted -- e.g. the
    workspace root would land inside SANA's own source. Distinct from
    DeepCodeServiceError (below), which is about one specific run.
    """


class DeepCodeServiceError(ValueError):
    """Raised for a bad call (e.g. an invalid project id) -- the route
    layer turns this into a 400, never a raw subprocess/OS exception.
    """


def validate_project_id(raw: str) -> str:
    """Returns [raw] unchanged if it's safe to use directly as a single
    path segment under the workspace root. Raises DeepCodeServiceError
    otherwise -- this is the only thing standing between a client-
    supplied string and a filesystem path, so it fails closed.

    Thin wrapper around build_workspace's shared implementation (also
    used by BuildAgent) that re-raises as this module's own error type,
    for backwards compatibility with existing callers/tests.
    """
    try:
        return _shared_validate_project_id(raw)
    except BuildWorkspaceError as e:
        raise DeepCodeServiceError(str(e)) from e


@dataclass
class DeepCodeRunResult:
    project_id: str
    status: str  # 'completed' | 'failed' | 'timeout'
    return_code: int | None
    stdout: str
    stderr: str
    workspace_path: str
    files: list[str] = field(default_factory=list)


class DeepCodeService:
    """One instance is stateless and reusable across requests -- all
    per-run state lives in the returned DeepCodeRunResult, nothing is
    held on self between calls.
    """

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()
        self._workspaces_root = self._resolve_workspaces_root()

    def _resolve_workspaces_root(self) -> Path:
        # Shared with BuildAgent (build_agent.py) via build_workspace.py
        # -- both write into the exact same workspaces root, using the
        # same safety guard. Re-raised as this module's own error type
        # for backwards compatibility with existing callers/tests.
        try:
            return resolve_workspaces_root(self._settings)
        except BuildWorkspaceConfigError as e:
            raise DeepCodeConfigError(str(e)) from e

    def _workspace_dir_for(self, project_id: str) -> Path:
        try:
            return project_dir_for(self._workspaces_root, project_id)
        except BuildWorkspaceError as e:
            raise DeepCodeServiceError(str(e)) from e

    async def run_task(self, *, project_id: str | None, task: str) -> DeepCodeRunResult:
        if not task or not task.strip():
            raise DeepCodeServiceError('task must not be empty.')

        resolved_project_id = project_id.strip() if project_id else _new_project_id()
        workspace = self._workspace_dir_for(resolved_project_id)
        workspace.mkdir(parents=True, exist_ok=True)

        argv = [
            self._settings.deepcode_bin,
            'exec',
            task,
            '--workspace',
            str(workspace),
            '--connection',
            self._settings.deepcode_connection,
            '--model',
            self._settings.deepcode_model,
            '--access',
            self._settings.deepcode_access,
        ]
        if self._settings.deepcode_trust:
            argv.append('--trust')

        logger.info(
            'DeepCode run starting: project_id=%s workspace=%s model=%s',
            resolved_project_id,
            workspace,
            self._settings.deepcode_model,
        )

        try:
            process = await asyncio.create_subprocess_exec(
                *argv,
                cwd=workspace,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except FileNotFoundError as e:
            raise DeepCodeConfigError(
                f"Couldn't run '{self._settings.deepcode_bin}' -- is DeepCode installed and DEEPCODE_BIN "
                'set correctly? (See .env.example.)'
            ) from e

        try:
            stdout_bytes, stderr_bytes = await asyncio.wait_for(
                process.communicate(), timeout=self._settings.deepcode_timeout_seconds
            )
            status = 'completed' if process.returncode == 0 else 'failed'
            return_code = process.returncode
        except TimeoutError:
            # Kill, then await the exit -- don't just move on and leave
            # a local-model inference process running unsupervised.
            process.kill()
            await process.wait()
            stdout_bytes, stderr_bytes = b'', b''
            status = 'timeout'
            return_code = None
            logger.warning(
                'DeepCode run timed out after %ss: project_id=%s',
                self._settings.deepcode_timeout_seconds,
                resolved_project_id,
            )

        stdout = _truncate(stdout_bytes.decode('utf-8', errors='replace'))
        stderr = _truncate(stderr_bytes.decode('utf-8', errors='replace'))

        logger.info(
            'DeepCode run finished: project_id=%s status=%s return_code=%s',
            resolved_project_id,
            status,
            return_code,
        )

        return DeepCodeRunResult(
            project_id=resolved_project_id,
            status=status,
            return_code=return_code,
            stdout=stdout,
            stderr=stderr,
            workspace_path=str(workspace),
            files=_list_files(workspace),
        )


def _truncate(text: str) -> str:
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    return text[:MAX_OUTPUT_CHARS] + f'\n\n[... truncated, output was {len(text)} chars ...]'



# DeepCode writes its own run log here on *every* invocation, success
# or not -- confirmed by live testing: a run that produced nothing at
# all still leaves logs/llm.jsonl behind. Excluded from _list_files so
# "did this run produce real project files" stays a meaningful
# question; without this, that check never fires (there's always at
# least this one file), and a caller -- the build_project tool's LLM
# included -- can be misled into reporting a "completed" build that
# made nothing. Real project files named exactly this would be
# vanishingly unlikely, and DeepCode's log format isn't something a
# generated project would want committed anyway.
_DEEPCODE_OWN_ARTIFACTS = {'logs/llm.jsonl'}


def _list_files(workspace: Path) -> list[str]:
    """Relative paths of every file DeepCode left behind, minus its own
    bookkeeping (see _DEEPCODE_OWN_ARTIFACTS) -- callers use this to
    tell a genuine build apart from a run that reported "completed" but
    produced nothing (a real failure mode seen in manual testing
    against a local model: the model describes a tool call as text
    instead of the tool actually running, or DeepCode's own agent
    claims success without writing anything).
    """
    if not workspace.exists():
        return []
    all_files = (
        str(p.relative_to(workspace)).replace('\\', '/') for p in workspace.rglob('*') if p.is_file()
    )
    return sorted(f for f in all_files if f not in _DEEPCODE_OWN_ARTIFACTS)
