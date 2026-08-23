"""
DeepCode Runtime Adapter — verified DeepCode CLI execution.

Invokes `deepcode exec` with `--json` and streams NDJSON events as
provider-neutral `BuildRunEvent` objects.

CLI command assembled from D1 discovery:
    deepcode exec
        --workspace <workspace_path>
        --json
        --access full-access
        --trust
        --connection <DEEPCODE_CONNECTION>
        "<prompt>"

NDJSON msg.type → BuildRunEvent.event_type mapping:
    turn_started          → start
    tool_started          → tool_start
    tool_completed        → tool_complete  (file_create / file_edit inferred from activity.kind)
    agent_message         → agent_message
    model_usage_recorded  → usage
    task_complete         → complete / error
    error                 → error
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import AsyncGenerator, Optional

from app.adapters.coding_agent_adapter import CodingAgentAdapter
from app.config import settings
from app.models.build_models import BuildRunEvent, BuildSpec
from app.services import workspace_runner

logger = logging.getLogger("backend.deepcode_runtime_adapter")

# Regex to extract session id from stderr: "session=<id> · status=<status> · ..."
_SESSION_RE = re.compile(r"session=([a-f0-9]+)")
_STATUS_RE = re.compile(r"status=(\w+)")


def _map_event_type(msg_type: str, activity_kind: Optional[str]) -> str:
    """Map a DeepCode NDJSON msg.type to a BuildRunEvent event_type."""
    mapping = {
        "turn_started": "start",
        "tool_started": "tool_start",
        "agent_message": "agent_message",
        "model_usage_recorded": "usage",
        "error": "error",
    }
    if msg_type == "tool_completed":
        if activity_kind in ("edit", "create"):
            return "file_edit"
        if activity_kind == "delete":
            return "file_delete"
        return "tool_complete"
    if msg_type == "task_complete":
        return "complete"
    return mapping.get(msg_type, "log")


class DeepCodeRuntimeAdapter(CodingAgentAdapter):
    """
    Executes the verified DeepCode CLI and streams provider-neutral
    BuildRunEvent objects. Every BuildRun produced by this adapter
    carries provider_label = "deepcode".
    """

    @property
    def provider_label(self) -> str:
        return "deepcode"

    async def run(
        self,
        spec: BuildSpec,
        run_id: str,
    ) -> AsyncGenerator[BuildRunEvent, None]:
        import os

        prompt = spec.to_prompt()
        workspace_path = os.path.abspath(os.path.normpath(spec.workspace_path))

        # Ensure workspace exists and is writable before invoking DeepCode
        os.makedirs(workspace_path, exist_ok=True)
        if not os.path.isdir(workspace_path):
            raise RuntimeError(f"Workspace directory does not exist: {workspace_path}")
        if not os.access(workspace_path, os.W_OK):
            raise RuntimeError(f"Workspace directory is not writable: {workspace_path}")

        command = [
            settings.DEEPCODE_BINARY_PATH,
            "exec",
            "--workspace", workspace_path,
            "--json",
            "--access", "full-access",
            "--trust",
            "--connection", settings.DEEPCODE_CONNECTION,
            prompt,
        ]

        logger.info(
            "DeepCodeRuntimeAdapter[%s] invoking: %s --workspace %s --connection %s ...",
            run_id, settings.DEEPCODE_BINARY_PATH, workspace_path, settings.DEEPCODE_CONNECTION,
        )
        logger.info(
            "DeepCodeRuntimeAdapter[%s] workspace absolute path: %s, exists: %s, writable: %s",
            run_id, workspace_path, os.path.isdir(workspace_path), os.access(workspace_path, os.W_OK),
        )

        sandbox_env = {
            "DEEPCODE_SANDBOX": os.environ.get("DEEPCODE_SANDBOX", "NOT SET"),
            "DEEPCODE_TRUST_WORKSPACE": os.environ.get("DEEPCODE_TRUST_WORKSPACE", "NOT SET"),
            "DEEPCODE_WORK_LOCALLY": os.environ.get("DEEPCODE_WORK_LOCALLY", "NOT SET"),
        }
        logger.info(
            "DeepCodeRuntimeAdapter[%s] sandbox environment: %s",
            run_id, sandbox_env,
        )

        seq = 0

        def _evt(event_type: str, message: str, raw_line: str = "", **details) -> BuildRunEvent:
            nonlocal seq
            seq += 1
            return BuildRunEvent(
                run_id=run_id,
                sequence=seq,
                event_type=event_type,
                message=message,
                details={"raw": raw_line, **details},
                provider=self.provider_label,
            )

        async for raw_line_event in workspace_runner.run_process(
            command=command,
            workspace_path=spec.workspace_path,
            run_id=run_id,
            timeout_seconds=settings.BUILD_RUN_TIMEOUT_SECONDS,
            max_output_bytes=settings.BUILD_RUN_MAX_OUTPUT_BYTES,
        ):
            raw = raw_line_event.details.get("raw", "")

            # The workspace_runner yields log / complete / error events;
            # parse NDJSON from the "log" lines to produce richer events.
            if raw_line_event.event_type == "log" and raw.startswith("{"):
                try:
                    obj = json.loads(raw)
                    msg = obj.get("msg", {})
                    msg_type: str = msg.get("type", "log")
                    activity_kind: Optional[str] = None

                    if msg_type == "tool_started":
                        activity_kind = (msg.get("activity") or {}).get("kind")

                    event_type = _map_event_type(msg_type, activity_kind)

                    # Build a human-readable message
                    if msg_type == "turn_started":
                        message = f"DeepCode turn started (run {run_id})"
                    elif msg_type == "tool_started":
                        message = f"Tool: {msg.get('name', '?')} — {msg.get('detail', '')}"
                    elif msg_type == "tool_completed":
                        name = msg.get("name", "?")
                        preview = msg.get("result_preview", "")
                        is_err = msg.get("is_error", False)
                        message = f"{'✗' if is_err else '✓'} {name}: {preview}"
                    elif msg_type == "agent_message":
                        message = msg.get("text", "")
                    elif msg_type == "model_usage_recorded":
                        usage = msg.get("usage", {})
                        message = (
                            f"Tokens — prompt: {usage.get('prompt_tokens', 0)}, "
                            f"completion: {usage.get('completion_tokens', 0)}"
                        )
                    elif msg_type == "task_complete":
                        stop = msg.get("stop_reason", "")
                        message = msg.get("final_text", f"Task complete ({stop})")
                        if stop == "error":
                            event_type = "error"
                    elif msg_type == "error":
                        message = msg.get("message", "Unknown error")
                    else:
                        message = raw

                    yield _evt(event_type, message, raw_line=raw, deepcode_msg=msg)
                    continue

                except json.JSONDecodeError:
                    pass

            # Non-JSON lines (e.g. stderr INFO lines) or runner synthetic events
            yield _evt(
                raw_line_event.event_type,
                raw_line_event.message,
                raw_line=raw,
            )

    async def cancel(self, run_id: str) -> None:
        logger.info("DeepCodeRuntimeAdapter.cancel(%s)", run_id)
        await workspace_runner.cancel_process(run_id)
