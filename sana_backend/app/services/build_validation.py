"""Project validators for the Build Agent (build_agent.py).

Each validator takes a generated project directory and returns a list
of human-readable problem strings (empty list = valid). Kept separate
from build_agent.py so the validation rules -- which are pure,
synchronous, and easy to unit-test in isolation -- aren't tangled up
with the agentic generation loop.

v1 scope is Chrome extensions only (per spec: "Chrome extension +
simple web project support is enough for the first working version") --
a generic web_app project has no structural validator yet, it's
considered valid as long as it has at least one file (checked by
build_agent.py itself before validation even runs).
"""

import json
from pathlib import Path

# Chrome's own permission list changes over time; rather than
# hard-coding (and inevitably going stale on) an allowlist, we just
# check the *shape* is right -- a list of strings. A wrong/unknown
# permission name is Chrome's problem to reject at load time, not
# something worth hard-failing a build over.
_REQUIRED_TOP_LEVEL = ('name', 'version')


def validate_chrome_extension(project_dir: Path) -> list[str]:
    errors: list[str] = []

    manifest_path = project_dir / 'manifest.json'
    if not manifest_path.exists():
        return ['manifest.json is missing -- every Chrome extension needs one at the project root.']

    raw = manifest_path.read_text(encoding='utf-8')
    try:
        manifest = json.loads(raw)
    except json.JSONDecodeError as e:
        return [f'manifest.json is not valid JSON: {e}']

    if not isinstance(manifest, dict):
        return ['manifest.json must contain a JSON object at the top level.']

    if manifest.get('manifest_version') != 3:
        errors.append('manifest.json must set "manifest_version": 3.')

    for field in _REQUIRED_TOP_LEVEL:
        if not manifest.get(field):
            errors.append(f'manifest.json is missing required field "{field}".')

    permissions = manifest.get('permissions')
    if permissions is not None:
        if not isinstance(permissions, list) or not all(isinstance(p, str) for p in permissions):
            errors.append('manifest.json "permissions" must be a list of strings.')

    errors.extend(_check_referenced_files(manifest, project_dir))

    return errors


def _check_referenced_files(manifest: dict, project_dir: Path) -> list[str]:
    errors: list[str] = []

    def _require(rel_path: object, where: str) -> None:
        if not isinstance(rel_path, str) or not rel_path.strip():
            errors.append(f'{where} is present but not a valid file path.')
            return
        # Manifest paths are always project-relative with forward
        # slashes; a leading '/' is still project-relative in Chrome's
        # own resolution, not an escape, so strip it before joining.
        candidate = project_dir / rel_path.lstrip('/')
        if not candidate.exists():
            errors.append(f'{where} references "{rel_path}", but that file does not exist.')

    action = manifest.get('action')
    if isinstance(action, dict) and action.get('default_popup'):
        _require(action['default_popup'], 'action.default_popup')

    background = manifest.get('background')
    if isinstance(background, dict) and background.get('service_worker'):
        _require(background['service_worker'], 'background.service_worker')

    content_scripts = manifest.get('content_scripts')
    if isinstance(content_scripts, list):
        for i, entry in enumerate(content_scripts):
            if not isinstance(entry, dict):
                errors.append(f'content_scripts[{i}] must be an object.')
                continue
            for key in ('js', 'css'):
                files = entry.get(key)
                if isinstance(files, list):
                    for f in files:
                        _require(f, f'content_scripts[{i}].{key}')

    icons = manifest.get('icons')
    if isinstance(icons, dict):
        for size, icon_path in icons.items():
            _require(icon_path, f'icons["{size}"]')

    return errors
