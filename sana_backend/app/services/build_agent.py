"""BuildAgent — Build mode's real code-generation engine.

Replaces relying on the external `deepcode exec` CLI (DeepCodeService)
for actually generating project files. That path is still present and
untouched (nothing deleted), but proved unreliable in practice: it
delegates writing files to a *second*, separate AI (DeepCode's own
internal agent, backed by a local Ollama model) which frequently either
narrates a plan without calling its own write tool, or SANA's own LLM
skips calling build_project altogether and fabricates a success story
(both confirmed by live testing, including an in-process diagnostic
using LiveKit's own testing harness -- see the conversation this was
built from).

The fix: stop the hand-off to a second, unreliable model. Give SANA's
own LLM (LiveKit Inference, already proven to reliably use structured
tool calling everywhere else in this backend) direct, granular file
tools, and run a normal agentic tool-calling loop -- the same pattern
ai_service.py's LiveKitInferenceProvider already uses for Build mode's
read-only source tools, just with write access scoped to one isolated
generated-project workspace.

Safety: every tool call is routed through build_workspace.py's
safe_relative_path -- path traversal ('../..', an absolute Windows/Unix
path, a symlink escape) is rejected before any filesystem operation
happens, the same guard file_access.py uses for SANA's own source tree.
"""

import logging
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from livekit.agents import APIConnectOptions, function_tool, inference
from livekit.agents.llm import ChatContext, FunctionTool, ToolContext, execute_function_call

from ..core.config import Settings, get_settings
from . import build_job_service as jobs
from .build_workspace import (
    BuildWorkspaceError,
    project_dir_for,
    resolve_workspaces_root,
    safe_relative_path,
)
from .build_validation import validate_chrome_extension

logger = logging.getLogger('sana-backend')

# 'chrome_extension' gets Manifest V3 structural validation
# (build_validation.py). 'web_app' is the general-purpose bucket for
# *everything else the user might ask for* -- not just literal HTML/
# CSS/JS: a Python script, a small CLI tool, a Flask/FastAPI backend, a
# Node app, a React app, whatever the task actually describes. It has
# no structural validator of its own beyond "at least one file exists"
# because "correct" means something different for every kind of
# project -- the LLM is free to create whatever files and folder
# structure the request calls for, nothing here restricts it to web
# content specifically.
PROJECT_TYPES = ('chrome_extension', 'web_app')
DEFAULT_PROJECT_TYPE = 'web_app'

_MAX_GENERATION_ROUNDS = 14
_MAX_FIX_ROUNDS = 6

_ARTIFACTS_DIRNAME = '_artifacts'


class BuildAgentError(Exception):
    """Raised for a setup problem serious enough that no generation was
    attempted (e.g. workspace misconfiguration) -- distinct from a
    build that ran and failed, which is reported via BuildAgentResult
    instead of raised.
    """


@dataclass
class BuildAgentResult:
    job_id: str
    status: str  # jobs.COMPLETED | jobs.FAILED
    files: list[str] = field(default_factory=list)
    workspace_path: str = ''
    artifact_path: str | None = None
    error: str | None = None


_BASE_INSTRUCTIONS = """
You are SANA's Build Agent -- a code-generation engine, not a conversational assistant. You have tools to
actually create and edit real files in a real project workspace: create_directory, create_file, read_file,
update_file, list_files, delete_file. Every path you pass to these tools is relative to the project root
(e.g. "main.py", "src/app.js") -- never use "..", an absolute path, or a drive letter.

Your job: given the task below, generate a complete, working set of files for it -- whatever kind of
project it actually calls for: a Python script or CLI tool, a Flask/FastAPI backend, a Node app, a React
app, a plain HTML/CSS/JS site, a Chrome extension, anything. Pick whatever language, framework, and file
layout genuinely fits the request; nothing here restricts you to web content. Concretely:
1. Decide what files the project needs, and in what language/framework, based on what was actually asked for.
2. Call create_file for each one, with real, working content -- not placeholders, not "TODO: implement this".
3. Call list_files if you need to check what already exists (e.g. when asked to modify an existing project).
4. Call read_file before update_file if you need to see a file's current content first.
5. When you are done creating/editing every file the task needs, say so in plain text with no further tool
   calls -- that is what ends the build.

Do not describe files in your text response instead of creating them -- the whole point of these tools is
that a create_file call is a real, persisted file, not a description of one. Do not claim a file exists
unless you actually called create_file or update_file for it in this session.
"""

_CHROME_EXTENSION_INSTRUCTIONS = """
This project is specifically a Chrome extension (Manifest V3). Requirements:
- Always create a manifest.json with "manifest_version": 3, a "name", and a "version".
- Every file manifest.json references (action.default_popup, background.service_worker,
  content_scripts[].js/css) must actually be created via create_file -- never reference a file you
  didn't create.
- Do NOT add an "icons" field to manifest.json, and do NOT create any .png/.jpg/.ico icon files.
  Your create_file tool only writes text, so an icon file you create would be text saved with an
  image extension, not a real image -- Chrome would show it broken. Icons are optional in Manifest
  V3; Chrome shows a default icon when none is specified, which is correct for this tool to produce.
- Prefer plain HTML/CSS/JavaScript (no build step, no bundler) so the extension can be loaded unpacked
  as-is via chrome://extensions -> Load unpacked.
- Include a short README.md explaining how to load it.
"""

_GENERAL_PROJECT_INSTRUCTIONS = """
This is a general-purpose project, not a Chrome extension -- there is no fixed structure to follow. Use
whatever language, framework, and file layout the task actually calls for (Python, Node, a static site,
a small game, a data script, anything). Include whatever entry point and setup a real developer would
expect (e.g. requirements.txt/package.json if the project needs one) and a short README.md explaining
what it is and how to run it.
"""


def _project_instructions(project_type: str) -> str:
    if project_type == 'chrome_extension':
        return _BASE_INSTRUCTIONS + _CHROME_EXTENSION_INSTRUCTIONS
    return _BASE_INSTRUCTIONS + _GENERAL_PROJECT_INSTRUCTIONS


def _make_file_tools(project_dir: Path) -> list[FunctionTool]:
    def _resolve(path: str) -> Path:
        try:
            return safe_relative_path(project_dir, path)
        except BuildWorkspaceError as e:
            # Re-raised as a plain ValueError so the caller's message
            # reaches the model as a normal tool result (see the
            # try/except in each tool below), not a crash.
            raise ValueError(str(e)) from e

    @function_tool
    async def create_directory(path: str) -> str:
        """Create a directory (and any missing parent directories) inside the project.

        Args:
            path: Directory path relative to the project root, e.g. "src" or "icons".
        """
        try:
            target = _resolve(path)
        except ValueError as e:
            return f'Error: {e}'
        target.mkdir(parents=True, exist_ok=True)
        return f'Created directory {path}'

    @function_tool
    async def create_file(path: str, content: str) -> str:
        """Create a file with the given content (overwrites if it already exists).
        Creates any missing parent directories automatically.

        Args:
            path: File path relative to the project root, e.g. "manifest.json" or "src/popup.js".
            content: The full file content to write.
        """
        try:
            target = _resolve(path)
        except ValueError as e:
            return f'Error: {e}'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        return f'Created {path} ({len(content)} chars)'

    @function_tool
    async def read_file(path: str) -> str:
        """Read a file's current content from the project.

        Args:
            path: File path relative to the project root.
        """
        try:
            target = _resolve(path)
        except ValueError as e:
            return f'Error: {e}'
        if not target.exists():
            return f"Error: '{path}' does not exist yet."
        if target.is_dir():
            return f"Error: '{path}' is a directory, not a file."
        try:
            return target.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            return f"Error: '{path}' is a binary file and can't be read as text."

    @function_tool
    async def update_file(path: str, content: str) -> str:
        """Replace an existing file's content. Prefer this over create_file when the file
        already exists and you're changing it, not starting it from scratch -- behavior is
        the same either way, but tells anyone reading the build log what actually happened.

        Args:
            path: File path relative to the project root.
            content: The full new content -- this replaces the entire file, it does not append.
        """
        try:
            target = _resolve(path)
        except ValueError as e:
            return f'Error: {e}'
        existed = target.exists()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        return f'Updated {path} ({len(content)} chars)' if existed else f'{path} did not exist yet -- created it.'

    @function_tool
    async def list_files(path: str = '') -> str:
        """List files and subdirectories in the project (or a subdirectory of it).

        Args:
            path: Directory relative to the project root, or empty/omitted for the project root.
        """
        try:
            target = _resolve(path) if path else project_dir
        except ValueError as e:
            return f'Error: {e}'
        if not target.exists():
            return f"'{path or '.'}' does not exist."
        if not target.is_dir():
            return f"'{path}' is a file, not a directory."
        entries = sorted(
            (f'{p.name}/' if p.is_dir() else p.name) for p in target.iterdir()
        )
        return '\n'.join(entries) if entries else '(empty)'

    @function_tool
    async def delete_file(path: str) -> str:
        """Delete a file from the project.

        Args:
            path: File path relative to the project root.
        """
        try:
            target = _resolve(path)
        except ValueError as e:
            return f'Error: {e}'
        if not target.exists():
            return f"'{path}' does not exist."
        if target.is_dir():
            return f"Error: '{path}' is a directory -- delete_file only removes files."
        target.unlink()
        return f'Deleted {path}'

    return [create_directory, create_file, read_file, update_file, list_files, delete_file]


def list_workspace_files(project_dir: Path) -> list[str]:
    if not project_dir.exists():
        return []
    return sorted(
        str(p.relative_to(project_dir)).replace('\\', '/')
        for p in project_dir.rglob('*')
        if p.is_file()
    )


# LiveKit Inference's own default per-call timeout (10s) is tuned for
# conversational replies -- too short for a single response that
# generates a whole file's contents through a tool call argument
# (confirmed by live testing: a real Chrome-extension build hit
# httpx.ReadTimeout well before the model finished streaming one
# multi-file response). Generation rounds get a much longer budget;
# retries stay modest since a genuinely hung connection shouldn't eat
# the whole build's time budget retrying it.
_LLM_CONN_OPTIONS = APIConnectOptions(timeout=120.0, max_retry=2, retry_interval=2.0)


async def _run_tool_loop(
    *, llm: inference.LLM, chat_ctx: ChatContext, tools: list[FunctionTool], max_rounds: int
) -> str:
    """Same shape as ai_service.py's LiveKitInferenceProvider tool loop
    (chat -> check tool_calls -> execute -> repeat), reused here rather
    than duplicated-and-drifted -- kept local instead of importing
    ai_service's private loop since the two now have slightly different
    call shapes (this one always has tools; that one doesn't when the
    mode has none) and duplicating ~15 lines is cheaper than coupling
    two unrelated modules over a private detail.
    """
    tool_ctx = ToolContext(tools=tools)
    for _ in range(max_rounds):
        response = await llm.chat(chat_ctx=chat_ctx, tools=tools, conn_options=_LLM_CONN_OPTIONS).collect()
        if not response.tool_calls:
            return (response.text or '').strip()
        for tool_call in response.tool_calls:
            result = await execute_function_call(tool_call, tool_ctx)
            chat_ctx.insert(result.fnc_call)
            if result.fnc_call_out:
                chat_ctx.insert(result.fnc_call_out)
    return 'Reached the maximum number of build steps without finishing.'


class BuildAgent:
    """One instance is stateless and reusable -- like DeepCodeService,
    all per-run state lives in the returned BuildAgentResult.
    """

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()
        self._workspaces_root = resolve_workspaces_root(self._settings)

    def workspace_path_for(self, job_id: str) -> Path:
        return project_dir_for(self._workspaces_root, job_id)

    def artifact_path_for(self, job_id: str) -> Path:
        return self._workspaces_root / _ARTIFACTS_DIRNAME / f'{job_id}.zip'

    async def run(self, *, job_id: str, task: str, project_type: str = DEFAULT_PROJECT_TYPE) -> BuildAgentResult:
        if project_type not in PROJECT_TYPES:
            project_type = DEFAULT_PROJECT_TYPE

        jobs.update_build_job_status(job_id, jobs.PLANNING)
        project_dir = self.workspace_path_for(job_id)

        jobs.update_build_job_status(job_id, jobs.CREATING_WORKSPACE)
        project_dir.mkdir(parents=True, exist_ok=True)

        tools = _make_file_tools(project_dir)
        llm = inference.LLM(model=self._settings.ai_model)
        try:
            jobs.update_build_job_status(job_id, jobs.GENERATING_FILES)
            existing = list_workspace_files(project_dir)
            context_note = (
                f'\n\nThe project already has these files (this is an edit to an existing project, '
                f'not a new one): {", ".join(existing)}'
                if existing
                else '\n\nThis is a brand-new, empty project.'
            )
            chat_ctx = ChatContext.empty()
            chat_ctx.add_message(role='system', content=_project_instructions(project_type))
            chat_ctx.add_message(role='user', content=task + context_note)

            await _run_tool_loop(llm=llm, chat_ctx=chat_ctx, tools=tools, max_rounds=_MAX_GENERATION_ROUNDS)

            files = list_workspace_files(project_dir)
            if not files:
                error = 'The build agent ran but did not create any files.'
                jobs.update_build_job_status(job_id, jobs.FAILED, error=error)
                return BuildAgentResult(
                    job_id=job_id, status=jobs.FAILED, workspace_path=str(project_dir), error=error
                )

            jobs.update_build_job_status(job_id, jobs.VALIDATING)
            errors = _validate(project_dir, project_type)

            if errors:
                jobs.update_build_job_status(job_id, jobs.FIXING)
                chat_ctx.add_message(
                    role='user',
                    content=(
                        'Validation found problems with the project. Fix them using your tools, '
                        'then confirm in plain text when done:\n- ' + '\n- '.join(errors)
                    ),
                )
                await _run_tool_loop(llm=llm, chat_ctx=chat_ctx, tools=tools, max_rounds=_MAX_FIX_ROUNDS)
                errors = _validate(project_dir, project_type)

            if errors:
                error = 'Build failed validation:\n' + '\n'.join(errors)
                jobs.update_build_job_status(job_id, jobs.FAILED, error=error)
                return BuildAgentResult(
                    job_id=job_id,
                    status=jobs.FAILED,
                    files=list_workspace_files(project_dir),
                    workspace_path=str(project_dir),
                    error=error,
                )

            jobs.update_build_job_status(job_id, jobs.PACKAGING)
            artifact_path = self._zip_project(job_id, project_dir)
            jobs.set_build_job_artifact(job_id, str(artifact_path))
            jobs.update_build_job_status(job_id, jobs.COMPLETED)

            return BuildAgentResult(
                job_id=job_id,
                status=jobs.COMPLETED,
                files=list_workspace_files(project_dir),
                workspace_path=str(project_dir),
                artifact_path=str(artifact_path),
            )
        except Exception:
            logger.exception('BuildAgent run failed unexpectedly: job_id=%s', job_id)
            error = 'An unexpected error occurred during the build. It has been logged for review.'
            jobs.update_build_job_status(job_id, jobs.FAILED, error=error)
            return BuildAgentResult(
                job_id=job_id, status=jobs.FAILED, workspace_path=str(project_dir), error=error
            )
        finally:
            await llm.aclose()

    def _zip_project(self, job_id: str, project_dir: Path) -> Path:
        artifact_path = self.artifact_path_for(job_id)
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        if artifact_path.exists():
            artifact_path.unlink()
        with zipfile.ZipFile(artifact_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for file_path in project_dir.rglob('*'):
                if file_path.is_file():
                    zf.write(file_path, arcname=file_path.relative_to(project_dir))
        return artifact_path


def _validate(project_dir: Path, project_type: str) -> list[str]:
    if project_type == 'chrome_extension':
        return validate_chrome_extension(project_dir)
    return []
