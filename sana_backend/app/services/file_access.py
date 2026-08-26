"""Safe, read-only access to the SANA project's own source code.

Used by Build mode's AI tools (see ai_service.py) so SANA can look at
the real sana_app/sana_backend code during a Build conversation instead
of only talking about it in the abstract.

Deliberately narrow: two allow-listed roots, a denylist for anything
sensitive (secrets, credentials, the database, dependency caches),
path-traversal protection, and a size cap. Read-only — there is no
write/delete function here at all, not just a permission check, per
the read-only-for-now decision.
"""

from pathlib import Path

# sana_backend/app/services/file_access.py -> parents[2] is sana_backend;
# sana_app is its sibling under the same parent directory.
_SANA_BACKEND_DIR = Path(__file__).resolve().parents[2]
_PROJECT_ROOTS: dict[str, Path] = {
    'sana_backend': _SANA_BACKEND_DIR,
    'sana_app': _SANA_BACKEND_DIR.parent / 'sana_app',
}

# Matched against any path *component* (not just the leaf) — so
# "sana_backend/.venv/lib/x.py" is blocked by the ".venv" component,
# not just an exact top-level match.
_DENYLIST_NAMES = {
    '.env',
    '.env.local',
    '.git',
    '.venv',
    'venv',
    'node_modules',
    '__pycache__',
    '.dart_tool',
    'build',
    '.idea',
    '.vscode',
    '.pytest_cache',
}
# Matched against the file's suffix — .db specifically because it's
# sana.db, which contains user emails and password hashes.
_DENYLIST_SUFFIXES = {'.db', '.pyc'}

MAX_FILE_BYTES = 50_000


class FileAccessError(ValueError):
    """Raised for any invalid/out-of-bounds/denylisted path request —
    caught by the tool wrapper in ai_service.py and turned into a
    message the model sees (e.g. "that file isn't accessible"),
    never a raw exception.
    """


def _is_denylisted(path: Path) -> bool:
    if path.suffix in _DENYLIST_SUFFIXES:
        return True
    return any(part in _DENYLIST_NAMES for part in path.parts)


def resolve_safe_path(raw_path: str) -> Path:
    """Validates [raw_path] (as given by the model, e.g.
    "sana_backend/app/main.py") and returns its resolved absolute Path.

    Raises FileAccessError if the path doesn't start with an
    allow-listed project name, escapes that project's directory
    (`..` traversal), or matches the denylist.
    """
    raw_path = raw_path.strip().strip('/\\')
    if not raw_path:
        raise FileAccessError('No path given.')

    parts = Path(raw_path).parts
    project_name = parts[0] if parts else ''
    root = _PROJECT_ROOTS.get(project_name)
    if root is None:
        raise FileAccessError(
            f"'{project_name}' isn't a project SANA can see. Use a path starting with "
            f"'sana_app' or 'sana_backend'."
        )

    candidate = (root / Path(*parts[1:])).resolve() if len(parts) > 1 else root.resolve()

    try:
        candidate.relative_to(root.resolve())
    except ValueError as e:
        raise FileAccessError('That path escapes the project directory.') from e

    if _is_denylisted(candidate):
        raise FileAccessError('That file or folder is not accessible (excluded for safety).')

    return candidate


def list_directory(raw_path: str) -> str:
    target = resolve_safe_path(raw_path)
    if not target.exists():
        raise FileAccessError(f"'{raw_path}' doesn't exist.")
    if not target.is_dir():
        raise FileAccessError(f"'{raw_path}' is a file, not a directory — use read_project_file instead.")

    entries: list[str] = []
    for child in sorted(target.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        if _is_denylisted(child):
            continue
        entries.append(f'{child.name}/' if child.is_dir() else child.name)

    if not entries:
        return f"'{raw_path}' is empty (or everything in it is excluded)."
    return '\n'.join(entries)


def read_file_contents(raw_path: str) -> str:
    target = resolve_safe_path(raw_path)
    if not target.exists():
        raise FileAccessError(f"'{raw_path}' doesn't exist.")
    if target.is_dir():
        raise FileAccessError(f"'{raw_path}' is a directory, not a file — use list_project_files instead.")

    raw_bytes = target.read_bytes()
    try:
        text = raw_bytes.decode('utf-8')
    except UnicodeDecodeError as e:
        raise FileAccessError(f"'{raw_path}' appears to be a binary file and can't be displayed.") from e

    if len(raw_bytes) > MAX_FILE_BYTES:
        truncated = raw_bytes[:MAX_FILE_BYTES].decode('utf-8', errors='ignore')
        return truncated + f'\n\n[... truncated, file is {len(raw_bytes)} bytes, showing first {MAX_FILE_BYTES} ...]'
    return text
