"""Provider-neutral models for Build Mode coding-agent execution."""

import hashlib
import json
from datetime import datetime, timezone
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

from app.models.architecture_models import ArchitectureSpec


class BuildSpec(BaseModel):
    """Fully-hydrated, immutable input assembled before any agent execution starts."""

    run_id: str
    project_id: str
    architecture_id: Optional[str] = None
    architecture_version: Optional[int] = None
    blueprint: Optional[ArchitectureSpec] = None
    specification: str
    acceptance_criteria: list[str] = Field(default_factory=list)
    technical_stack: dict[str, str] = Field(default_factory=dict)
    repository_rules: list[str] = Field(default_factory=list)
    test_requirements: list[str] = Field(default_factory=list)
    workspace_path: str
    approved_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    approved_by: str  # user_id

    def blueprint_hash(self) -> Optional[str]:
        """Stable SHA-256 of the blueprint JSON for approval-mismatch detection."""
        if self.blueprint is None:
            return None
        blueprint_json = json.dumps(self.blueprint.model_dump(mode="json"), sort_keys=True)
        return hashlib.sha256(blueprint_json.encode()).hexdigest()

    def to_prompt(self) -> str:
        """Assemble a structured natural-language prompt for the coding agent."""
        lines: list[str] = [
            "# Soul Build Mode — Approved Execution",
            "",
            "You are generating a complete, runnable project for the user.",
            "Write real source files, not only an explanation or markdown plan.",
            "Do not leave placeholder TODOs for core requested behavior.",
            "Prefer a small, coherent implementation over many disconnected files.",
            "Include a README with run instructions, architecture notes, and any known limitations.",
            "If tests are practical for the chosen stack, include at least one smoke test or validation script.",
            "",
            f"## Project specification",
            self.specification,
            "",
        ]

        if self.blueprint is not None:
            lines += [
                "## Approved Architecture Blueprint",
                f"Architecture: {self.blueprint.architecture_id}",
                f"Version: {self.blueprint.version}",
                "",
                "### Components",
            ]
            for comp in self.blueprint.components:
                tech = comp.technology or "unspecified"
                lines.append(f"- **{comp.name}** ({comp.type}) — technology: {tech}")

            if self.blueprint.connections:
                lines += ["", "### Connections"]
                for conn in self.blueprint.connections:
                    lines.append(
                        f"- {conn.source_id} → {conn.target_id}"
                        + (f" [{conn.protocol}]" if conn.protocol else "")
                    )

        if self.acceptance_criteria:
            lines += ["", "## Acceptance criteria"]
            for criterion in self.acceptance_criteria:
                lines.append(f"- {criterion}")

        if self.technical_stack:
            lines += ["", "## Technical stack"]
            for key, value in self.technical_stack.items():
                lines.append(f"- {key}: {value}")

        if self.test_requirements:
            lines += ["", "## Test requirements"]
            for req in self.test_requirements:
                lines.append(f"- {req}")

        if self.repository_rules:
            lines += ["", "## Repository rules"]
            for rule in self.repository_rules:
                lines.append(f"- {rule}")

        lines += [
            "",
            "## Workspace",
            f"All files must be written inside: `{self.workspace_path}`",
            "Do not write files outside this directory.",
            "When complete, leave the workspace containing the final app files only, plus useful docs/tests.",
        ]

        return "\n".join(lines)


class BuildRunEvent(BaseModel):
    """Provider-neutral event emitted during coding agent execution."""

    run_id: str
    sequence: int
    event_type: Literal[
        "start",
        "tool_start",
        "tool_complete",
        "file_create",
        "file_edit",
        "file_delete",
        "command",
        "test_result",
        "log",
        "agent_message",
        "usage",
        "complete",
        "error",
        "cancelled",
    ]
    message: str
    details: dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    provider: str  # "deepcode" | "prototype_scaffold"


__all__ = ["BuildSpec", "BuildRunEvent"]
