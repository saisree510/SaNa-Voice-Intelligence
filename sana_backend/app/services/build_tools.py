"""AI-callable tools exposed only in Build mode — let SANA look at the
real sana_app/sana_backend source during a Build conversation instead
of only discussing it in the abstract.

Read-only (see file_access.py) — there's no write/delete tool here.
Each tool catches FileAccessError and returns it as the tool's *result*
string rather than letting it raise, since the model needs to see "that
path isn't accessible" as a normal answer it can react to (e.g. by
trying a different path), not a crash.
"""

from livekit.agents import function_tool

from .file_access import FileAccessError, list_directory, read_file_contents


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
