"""Persistence-facing models for Architecture Blueprint storage."""

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.architecture_models import ArchitectureSpec, CanvasOperation, CanvasValidationError, ID_PATTERN


class ArchitectureVisibility(str, Enum):
    PRIVATE = "private"


class ArchitectureRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    architecture_id: str = Field(pattern=ID_PATTERN)
    user_id: str
    title: str = Field(min_length=1, max_length=160)
    conversation_id: Optional[str] = None
    project_id: Optional[str] = None
    visibility: ArchitectureVisibility = ArchitectureVisibility.PRIVATE
    current_version: int = Field(default=1, ge=1)
    current_blueprint: ArchitectureSpec
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ArchitectureVersionRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    version_id: str = Field(pattern=ID_PATTERN)
    architecture_id: str = Field(pattern=ID_PATTERN)
    user_id: str
    version_number: int = Field(ge=1)
    blueprint: ArchitectureSpec
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class CanvasEventRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_id: str = Field(pattern=ID_PATTERN)
    architecture_id: str = Field(pattern=ID_PATTERN)
    user_id: str
    architecture_version: int = Field(ge=1)
    sequence_number: int = Field(ge=1)
    idempotency_key: str = Field(min_length=1, max_length=120)
    event_type: str = Field(min_length=1, max_length=80)
    operation: CanvasOperation
    validation_errors: list[CanvasValidationError] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class CanvasSnapshotRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snapshot_id: str = Field(pattern=ID_PATTERN)
    architecture_id: str = Field(pattern=ID_PATTERN)
    user_id: str
    architecture_version: int = Field(ge=1)
    sequence_number: int = Field(ge=0)
    blueprint: ArchitectureSpec
    scene: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


__all__ = [
    "ArchitectureRecord",
    "ArchitectureVersionRecord",
    "ArchitectureVisibility",
    "CanvasEventRecord",
    "CanvasSnapshotRecord",
]
