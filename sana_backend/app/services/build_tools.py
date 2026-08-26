"""AI-callable tools exposed only in Build mode.

Three kinds:
- Read-only source browsing (list_project_files, read_project_file) —
  let SANA look at the real sana_app/sana_backend source during a Build
  conversation instead of only discussing it in the abstract. See
  file_access.py; there is no write/delete tool for SANA's own source,
  not just a permission check.
- make_build_project_tool / make_check_build_progress_tool — *factories*,
  not plain tools, because they need to remember which build job/
  workspace this conversation is building into across turns (see
  make_build_project_tool's own docstring). Everything else in this
  module is stateless and safe to share as bare module-level
  @function_tools; these two aren't, so they aren't ones.

Both are powered by BuildAgent (build_agent.py) — SANA's own LLM
actually creating real files via real tools, tracked in the build_jobs
table (build_job_service.py). DeepCodeService (the external
`deepcode exec` CLI path) is still here and still works via
POST /api/build/run, it's just no longer what a Build-mode
*conversation* invokes — proved unreliable for that in practice (see
build_agent.py's module docstring).

build_project does NOT wait for the build to finish before returning —
a real multi-file generation can take minutes, and awaiting that
inside one conversational turn proved to actively cause hallucination
in practice: a user naturally keeps talking while it's still running
("okay", "is it done?"), each of those messages interrupts the
in-flight turn (see voice_agent.py's VAD interruption config), and the
*next* turn has no tool result to report — so the model, asked
point-blank "is it done", guessed, confidently, wrongly (confirmed via
live testing: it claimed "I have finished building" ~20 seconds into a
build that didn't actually complete for another 7 minutes). Splitting
build_project (start, return immediately) from check_build_progress
(a real status lookup, callable as often as needed) means there is
always a real answer available before SANA has to say anything about
status — see BUILD_VOICE_TOOLS_NOTE / BUILD_TOOLS_NOTE in
app/modes/build.py for the instruction that makes calling it mandatory.

Each tool catches its underlying error type and returns it as the
tool's *result* string rather than letting it raise, since the model
needs to see "that path isn't accessible" / "that build failed" as a
normal answer it can react to, not a crash.
"""

import asyncio
import logging

from livekit.agents import function_tool
from livekit.agents.llm import FunctionTool

# asyncio only holds a *weak* reference to a task once nothing else
# references it -- a bare `asyncio.create_task(...)` with the result
# discarded is liable to get garbage-collected mid-run (a well-known
# asyncio pitfall, called out in the stdlib docs). This set is that
# "something else": every background build task is added here and
# removed via its own done-callback once finished, so it survives for
# its full run regardless of what happens to the function that started it.
_background_build_tasks: set[asyncio.Task] = set()

from . import build_job_service as jobs
from .build_agent import BuildAgent, PROJECT_TYPES, list_workspace_files
from .build_workspace import new_project_id
from .file_access import FileAccessError, list_directory, read_file_contents

logger = logging.getLogger('sana-backend')


@function_tool
async def list_project_files(directory: str) -> str:
    """List the files and subdirectories inside a directory of the SANA
    project's own source code.

    Args:
        directory: Path relative to the project root, starting with
            'sana_app' or 'sana_backend' — e.g. 'sana_backend/app' or
            'sana_app/lib/features'.
    """
    try:
        return list_directory(directory)
    except FileAccessError as e:
        return f'Error: {e}'


@function_tool
async def read_project_file(path: str) -> str:
    """Read the contents of a source file in the SANA project's own
    codebase.

    Args:
        path: Path relative to the project root, starting with
            'sana_app' or 'sana_backend' — e.g. 'sana_backend/app/main.py'.
    """
    try:
        return read_file_contents(path)
    except FileAccessError as e:
        return f'Error: {e}'


BUILD_MODE_TOOLS = [list_project_files, read_project_file]


def make_build_project_tool(
    build_agent: BuildAgent,
    job_id_holder: dict[str, str | None],
    *,
    user_id: str | None = None,
    conversation_id: str | None = None,
) -> FunctionTool:
    """Returns a fresh @function_tool bound to *this* conversation/call.

    [job_id_holder] is a single-key mutable dict (`{'job_id': ...}`),
    not a plain argument, for the same reason it was before this was
    rewired onto BuildAgent: the workspace has to stay the *same* one
    across every build_project call in one conversation ("make the
    popup dark mode" should edit the existing project, not start a new
    one), and the model can't be trusted to pass a stable id back
    itself — it's given none to pass. First call: holder's job_id is
    None, a BuildJob is created (or, with no user_id to own it — an
    old voice client that didn't send one — an untracked workspace id
    is minted instead) and this closure remembers it by mutating the
    holder in place; every call after that reuses it and continues
    building into the same project directory. Callers own the holder's
    lifetime — text chat seeds it with the conversation_id upfront
    (see ai_service.py); voice starts it empty and lets the first call
    populate it (no conversation_id exists before the first turn is
    recorded — see voice_agent.py).

    [user_id]/[conversation_id] are who the build belongs to and, if
    known, which conversation triggered it — recorded on the BuildJob
    row so the REST API (app/api/build.py) and the Flutter Build
    Workspace panel can find and show it. Both may be None (an
    unauthenticated-context or pre-first-turn voice call); the tool
    still works, it just can't persist a trackable job.
    """

    def _get_or_create_job(project_name: str, project_type: str, task: str) -> str:
        job_id = job_id_holder.get('job_id')
        # job_id may already be set (text chat pre-seeds it with
        # conversation_id — see ai_service.py) without a BuildJob row
        # existing for it yet, so "do we need to create one" is "is
        # there a row for this id", not just "is job_id None".
        existing_job = jobs.get_build_job(job_id) if job_id else None
        if existing_job is None:
            if user_id:
                job = jobs.create_build_job(
                    user_id=user_id,
                    conversation_id=conversation_id,
                    project_name=project_name.strip() or 'project',
                    project_type=project_type,
                    request_text=task,
                    job_id=job_id,
                )
                job_id = job.id
            else:
                job_id = job_id or new_project_id()
                logger.warning('build_project called with no user_id — this build will not be trackable via the API.')
            job_id_holder['job_id'] = job_id
        return job_id

    def _run_in_background(job_id: str, task: str, project_type: str) -> None:
        async def _run() -> None:
            try:
                await build_agent.run(job_id=job_id, task=task, project_type=project_type)
            except Exception:
                # BuildAgent.run already catches its own errors and
                # records FAILED on the job -- this is a last-resort
                # backstop (mirrors app/api/build.py's background-task
                # handler) so a genuinely unexpected bug still leaves
                # the job in a terminal state instead of stuck forever,
                # and never crashes the surrounding conversation (this
                # runs detached from the tool call that started it).
                logger.exception('Unexpected error running build job %s in the background.', job_id)
                jobs.update_build_job_status(
                    job_id, jobs.FAILED, error='An unexpected error occurred during the build.'
                )

        bg_task = asyncio.create_task(_run())
        _background_build_tasks.add(bg_task)
        bg_task.add_done_callback(_background_build_tasks.discard)

    @function_tool
    async def build_project(task: str, project_name: str, project_type: str) -> str:
        """Starts actually building something: generates real files for the
        current project inside a dedicated build workspace, using SANA's own
        file-creation tools — not a description, an actual project on disk.
        Use this once you and the user have agreed on what to build (or what
        to change/add next) — don't just describe code, actually call this to
        produce it. Safe to call again in the same conversation to keep
        building on the same project (add a feature, fix something, restyle
        something) — it continues in the same workspace rather than starting
        over.

        IMPORTANT: this does not wait for the build to finish -- real builds
        can take several minutes. It only confirms the build has *started*.
        Do not say the build is "done", "finished", or "ready" based on this
        result alone -- call check_build_progress to find out for real,
        every time, no matter how much time feels like it has passed.

        Args:
            task: A clear, self-contained description of what to build
                or change right now — enough detail to act on without
                the rest of the conversation (e.g. "Create a Chrome
                extension that blocks a domain the user enters", not
                "make the thing we discussed").
            project_name: A short, filesystem-safe name for the project,
                e.g. "FocusBlock" — used to name the downloadable ZIP.
                Keep it the same across calls that edit the same project.
            project_type: "chrome_extension" if the user specifically wants a Manifest V3
                Chrome extension; "web_app" for literally anything else they ask to
                build -- a Python script, a Flask/FastAPI backend, a Node app, a React
                app, a plain HTML/CSS/JS site, a CLI tool, whatever it actually is.
                "web_app" is not limited to web content, it just means "not a Chrome
                extension" -- always pick it unless a Chrome extension was specifically
                requested.
        """
        if project_type not in PROJECT_TYPES:
            project_type = 'web_app'

        try:
            job_id = _get_or_create_job(project_name, project_type, task)
        except Exception as e:
            # _get_or_create_job only touches the database (create_build_job /
            # get_build_job) -- BuildWorkspaceConfigError/BuildAgentError can't
            # come from here (those are BuildAgent construction/run-time
            # errors, already resolved before this tool exists — see
            # ai_service.py/voice_agent.py). A bare Exception catch is still
            # right here: a DB hiccup shouldn't crash the conversation either.
            logger.exception('Could not start build job: %s', e)
            return "Couldn't start the build right now — a problem on SANA's side, not yours. Try again shortly."

        _run_in_background(job_id, task, project_type)

        return (
            'Started the build — it is running now, this can take a few minutes for a real project. '
            'Do not tell the user it is finished yet. Call check_build_progress (with no arguments needed) '
            'to get a real status update, whenever the user asks or before you say anything about it being done.'
        )

    return build_project


def make_check_build_progress_tool(build_agent: BuildAgent, job_id_holder: dict[str, str | None]) -> FunctionTool:
    """Returns a fresh @function_tool that reports the *real*, current
    status of the build started by build_project in this same
    conversation (via the shared [job_id_holder] — see
    make_build_project_tool's docstring for why it's a shared holder,
    not a plain argument). This is the only honest source of "is it
    done yet" — build_project itself returns before the build finishes.

    [build_agent] is the *same* instance build_project was given (both
    factories are always called together for one conversation — see
    ai_service.py/voice_agent.py) so listing a completed build's files
    doesn't re-resolve/re-validate the workspace root on every check.
    """

    @function_tool
    async def check_build_progress() -> str:
        """Checks the real, current status of the build started by
        build_project in this conversation — call this whenever the user
        asks if it's done, ready, or how it's going, and before saying
        anything about completion or failure. Never guess; always check.
        """
        job_id = job_id_holder.get('job_id')
        if job_id is None:
            return 'No build has been started in this conversation yet.'

        job = jobs.get_build_job(job_id)
        if job is None:
            return "That build can't be found — it may not have been trackable (no signed-in user)."

        if job.status == jobs.COMPLETED:
            try:
                files = list_workspace_files(build_agent.workspace_path_for(job_id))
            except Exception:
                files = []
            artifact_note = f' Packaged as {job.project_name}.zip, ready to download.' if job.artifact_path else ''
            files_note = f' Files: {", ".join(files)}.' if files else ''
            return f'The build is complete.{files_note}{artifact_note}'

        if job.status == jobs.FAILED:
            return f'The build failed. {job.error or "No further details available."}'

        # Still in progress -- PENDING/PLANNING/CREATING_WORKSPACE/
        # GENERATING_FILES/VALIDATING/FIXING/PACKAGING. Use the DB's own
        # status label rather than a separate copy of it here.
        return f'Still working on it — current step: {job.status.replace("_", " ").title()}. Not done yet.'

    return check_build_progress
