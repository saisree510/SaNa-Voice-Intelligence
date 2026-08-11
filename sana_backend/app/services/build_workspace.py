"""Shared safe-workspace primitives for everything that writes generated
project files — DeepCodeService (deepcode_service.py) and the native
BuildAgent (build_agent.py) both build on this rather than each
re-implementing path safety.

Extracted from DeepCodeService's original implementation with no
behavior change there; see its own module docstring for the safety
properties this exists to guarantee (isolated root, guarded against
ever resolving inside sana_app/sana_backend, project ids validated
before ever touching a filesystem path).
"""

import re
import uuid
from pathlib import Path

from ..core.config import Settings

# 1-64 chars, letters/digits/underscore/hyphen, must start with a
# letter or digit -- safe as a single path segment on every OS this
# might run on, and unambiguous (no leading '.', no way to spell '..').
PROJECT_ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')


class BuildWorkspaceConfigError(RuntimeError):
    """Raised when the configured/default workspace root itself is
    unsafe (e.g. resolves inside sana_app/sana_backend) -- serious
    enough that nothing should proceed, not just this one call.
    """


class BuildWorkspaceError(ValueError):
    """Raised for a bad per-call input (invalid project id, path
    escaping the project directory) -- the caller turns this into a
    4xx, never a raw filesystem exception.
    """


def new_project_id() -> str:
    # Short, still effectively unique for this use (one workspace dir
    # per build, not a security token) -- readable in logs/URLs unlike
    # a full uuid4.
    return uuid.uuid4().hex[:12]


def validate_project_id(raw: str) -> str:
    """Returns [raw] unchanged if it's safe to use directly as a single
    path segment under the workspace root. Raises BuildWorkspaceError
    otherwise -- this is the only thing standing between a client- or
    model-supplied string and a filesystem path, so it fails closed.
    """
    if not PROJECT_ID_RE.match(raw):
        raise BuildWorkspaceError(
            "Invalid project id -- use 1-64 letters, digits, '_' or '-', starting with a letter or digit."
        )
    return raw


def resolve_workspaces_root(settings: Settings) -> Path:
    """The directory every generated project lives under -- a sibling
    of sana_app/ and sana_backend/ by default (BUILD_WORKSPACES_ROOT
    overrides), never inside either. Raises BuildWorkspaceConfigError
    (regardless of whether the root came from config or the default)
    if it would ever resolve inside one of them.
    """
    # build_workspace.py -> parents[1] is app, parents[2] is sana_backend.
    sana_backend_dir = Path(__file__).resolve().parents[2]
    sana_app_dir = (sana_backend_dir.parent / 'sana_app').resolve()

    configured = settings.build_workspaces_root
    root = Path(configured).expanduser().resolve() if configured else (sana_backend_dir.parent / 'sana-builds').resolve()

    for guarded in (sana_backend_dir, sana_app_dir):
        if root == guarded or guarded in root.parents:
            raise BuildWorkspaceConfigError(
                f'Refusing to use build workspace root {root} -- it is inside {guarded}. '
                'Set SANA_BUILD_WORKSPACES_ROOT to a location outside sana_app/sana_backend.'
            )

    root.mkdir(parents=True, exist_ok=True)
    return root


def project_dir_for(workspaces_root: Path, project_id: str) -> Path:
    """The directory a specific project lives in, validated and
    re-checked against [workspaces_root] -- defense in depth alongside
    validate_project_id, the same belt-and-suspenders pattern
    file_access.py uses for Build mode's read-only source-browsing tools.
    """
    validate_project_id(project_id)
    candidate = (workspaces_root / project_id).resolve()
    try:
        candidate.relative_to(workspaces_root)
    except ValueError as e:
        raise BuildWorkspaceError('Invalid project id.') from e
    return candidate


def safe_relative_path(project_dir: Path, raw_relative_path: str) -> Path:
    """Resolves [raw_relative_path] (as given by the model, e.g.
    "popup.html" or "src/content.js") against [project_dir] and
    verifies the result is still inside it -- rejects '..' traversal,
    absolute paths (C:\\Windows, /etc/, a home directory) escaping the
    project, symlink tricks, all of it, the same way file_access.py's
    resolve_safe_path guards SANA's own source tree.
    """
    raw = (raw_relative_path or '').strip().strip('/\\')
    if not raw:
        raise BuildWorkspaceError('No path given.')
    if Path(raw).is_absolute():
        raise BuildWorkspaceError('Absolute paths are not allowed -- use a path relative to the project.')

    candidate = (project_dir / Path(raw)).resolve()
    try:
        candidate.relative_to(project_dir.resolve())
    except ValueError as e:
        raise BuildWorkspaceError('That path escapes the project directory.') from e
    return candidate
