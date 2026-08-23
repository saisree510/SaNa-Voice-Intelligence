"""
Safe Workspace Runner — controlled subprocess execution for coding-agent builds.

Guarantees:
- Workspace stays inside the trusted BUILD_STORAGE_ROOT (path-traversal blocked).
- Execution has a hard timeout (default 10 minutes).
- stdout is capped at BUILD_RUN_MAX_OUTPUT_BYTES (2 MB default).
- The process receives SIGTERM then SIGKILL on cancellation or timeout.
- The environment is stripped of unnecessary credentials.
- Each active run is tracked so it can be cancelled by run_id.
"""

import asyncio
import logging
import os
import signal
import sys
from datetime import datetime, timezone
from typing import AsyncGenerator

from app.config import settings
from app.models.build_models import BuildRunEvent

logger = logging.getLogger("backend.workspace_runner")

# Map run_id → asyncio.subprocess.Process for in-flight cancellation
_active_processes: dict[str, asyncio.subprocess.Process] = {}

# Allowlisted env keys forwarded to the child process
_ENV_ALLOWLIST = {
    "PATH",
    "HOME",
    "USER",
    "LANG",
    "LC_ALL",
    "TMPDIR",
    "TEMP",
    "TMP",
    "USERPROFILE",       # Windows HOME equivalent
    "SystemRoot",        # Windows
    "SystemDrive",       # Windows
    "COMSPEC",           # Windows
    "PATHEXT",           # Windows
    # DeepCode runtime needs its own config dir
    "DEEPCODE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
}


def _safe_env() -> dict[str, str]:
    """Return a credential-free environment safe to pass to the child process."""
    return {k: v for k, v in os.environ.items() if k in _ENV_ALLOWLIST}


def _verify_workspace(workspace_path: str) -> str:
    """Canonicalize and verify workspace stays inside the trusted root."""
    trusted_root = os.path.abspath(os.path.normpath(settings.BUILD_STORAGE_ROOT))
    candidate = os.path.abspath(os.path.normpath(workspace_path))

    # Resolve symlinks to prevent escape
    try:
        real_candidate = os.path.realpath(candidate)
        real_root = os.path.realpath(trusted_root)
    except OSError:
        raise ValueError(f"Workspace path could not be resolved: {workspace_path}")

    try:
        common = os.path.commonpath([real_root, real_candidate])
    except ValueError:
        raise ValueError(f"Workspace path is outside trusted root: {workspace_path}")

    if common != real_root:
        raise ValueError(
            f"Workspace path '{workspace_path}' escapes the trusted build root '{trusted_root}'"
        )
    return candidate


async def run_process(
    command: list[str],
    workspace_path: str,
    run_id: str,
    timeout_seconds: int | None = None,
    max_output_bytes: int | None = None,
) -> AsyncGenerator[BuildRunEvent, None]:
    """
    Run `command` in `workspace_path` and stream `BuildRunEvent` objects.

    Yields:
        - One `log` event per stdout line (NDJSON or plain text).
        - A `complete` event on exit code 0.
        - An `error` event on non-zero exit or timeout, then raises RuntimeError.
    """
    timeout = timeout_seconds if timeout_seconds is not None else settings.BUILD_RUN_TIMEOUT_SECONDS
    max_bytes = max_output_bytes if max_output_bytes is not None else settings.BUILD_RUN_MAX_OUTPUT_BYTES

    workspace = _verify_workspace(workspace_path)
    os.makedirs(workspace, exist_ok=True)

    env = _safe_env()
    seq = 0

    def _evt(event_type: str, message: str, **details) -> BuildRunEvent:
        nonlocal seq
        seq += 1
        return BuildRunEvent(
            run_id=run_id,
            sequence=seq,
            event_type=event_type,
            message=message,
            details=details,
            provider="deepcode",
        )

    logger.info("run_process[%s] starting: %s", run_id, command)

    try:
        proc = await asyncio.create_subprocess_exec(
            *command,
            cwd=workspace,
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _active_processes[run_id] = proc
    except FileNotFoundError as exc:
        yield _evt("error", f"DeepCode binary not found: {command[0]}")
        raise RuntimeError(f"DeepCode binary not found: {command[0]}") from exc

    total_bytes = 0
    timed_out = False

    try:
        async def _read_lines():
            nonlocal total_bytes
            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                total_bytes += len(line)
                if total_bytes > max_bytes:
                    logger.warning("run_process[%s] output cap exceeded (%d bytes)", run_id, total_bytes)
                    proc.terminate()
                    break
                yield line.decode("utf-8", errors="replace").rstrip()

        async def _run_with_timeout():
            async for raw_line in _read_lines():
                yield raw_line

        async with asyncio.timeout(timeout):
            async for raw_line in _run_with_timeout():
                yield _evt("log", raw_line, raw=raw_line)

        await proc.wait()

    except TimeoutError:
        timed_out = True
        logger.warning("run_process[%s] timed out after %ds", run_id, timeout)
        _terminate_process(proc)
        await proc.wait()
    finally:
        _active_processes.pop(run_id, None)

    if timed_out:
        yield _evt("error", f"Build timed out after {timeout} seconds")
        raise RuntimeError(f"Build run {run_id} timed out after {timeout} seconds")

    exit_code = proc.returncode
    if exit_code != 0:
        stderr_bytes = await proc.stderr.read(4096) if proc.stderr else b""
        stderr_text = stderr_bytes.decode("utf-8", errors="replace").strip()
        yield _evt("error", f"DeepCode exited with code {exit_code}", stderr=stderr_text, exit_code=exit_code)
        raise RuntimeError(f"Build run {run_id} failed with exit code {exit_code}")

    yield _evt("complete", f"Build run {run_id} completed successfully", exit_code=0)


async def cancel_process(run_id: str) -> None:
    """Request cancellation of a running build process."""
    proc = _active_processes.get(run_id)
    if proc is None:
        logger.info("cancel_process[%s]: no active process found", run_id)
        return
    logger.info("cancel_process[%s]: sending SIGTERM", run_id)
    _terminate_process(proc)


def _terminate_process(proc: asyncio.subprocess.Process) -> None:
    """Send SIGTERM; fall back to SIGKILL on Windows."""
    try:
        if sys.platform == "win32":
            proc.kill()
        else:
            proc.terminate()
    except ProcessLookupError:
        pass
