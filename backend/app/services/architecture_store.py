import json
import os
import uuid
from datetime import datetime, timezone
from threading import Lock
from typing import Optional

from supabase import create_client

from app.auth.auth_bearer import normalize_user_id, user_id_aliases
from app.models.architecture_models import ArchitectureSpec
from app.models.architecture_storage_models import (
    ArchitectureRecord,
    ArchitectureVersionRecord,
    CanvasEventRecord,
    CanvasSnapshotRecord,
)


def new_architecture_id(prefix: str = "arch") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:20]}"


class DuplicateIdempotencyError(ValueError):
    def __init__(self, existing_event: CanvasEventRecord):
        super().__init__("Duplicate canvas event idempotency key")
        self.existing_event = existing_event


class SequenceConflictError(ValueError):
    pass


class ArchitectureStore:
    def __init__(self, trusted_root: str, db_path: Optional[str] = None):
        self._trusted_root = os.path.abspath(os.path.normpath(trusted_root))
        self._db_path = os.path.abspath(os.path.normpath(db_path or os.path.join(self._trusted_root, ".soul_architectures.json")))
        self._lock = Lock()
        os.makedirs(self._trusted_root, exist_ok=True)
        if not self._is_within(self._trusted_root, self._db_path):
            raise ValueError("Architecture database path must stay within the trusted root")

    def create_architecture(self, record: ArchitectureRecord) -> ArchitectureRecord:
        with self._lock:
            data = self._read_data_unlocked()
            data["architectures"][record.architecture_id] = record.model_dump(mode="json")
            self._write_data_unlocked(data)
        return record

    def get_architecture(self, architecture_id: str) -> Optional[ArchitectureRecord]:
        data = self._read_data()
        item = data["architectures"].get(architecture_id)
        return ArchitectureRecord.model_validate(item) if item else None

    def list_architectures_for_user(self, user_id: str) -> list[ArchitectureRecord]:
        aliases = user_id_aliases(user_id)
        data = self._read_data()
        records = [ArchitectureRecord.model_validate(item) for item in data["architectures"].values()]
        records = [record for record in records if record.user_id in aliases]
        return sorted(records, key=lambda record: record.updated_at, reverse=True)

    def update_architecture(self, record: ArchitectureRecord) -> ArchitectureRecord:
        record.updated_at = datetime.now(timezone.utc)
        with self._lock:
            data = self._read_data_unlocked()
            if record.architecture_id not in data["architectures"]:
                raise KeyError(record.architecture_id)
            data["architectures"][record.architecture_id] = record.model_dump(mode="json")
            self._write_data_unlocked(data)
        return record

    def create_version(self, version: ArchitectureVersionRecord) -> ArchitectureVersionRecord:
        with self._lock:
            data = self._read_data_unlocked()
            data["versions"][version.version_id] = version.model_dump(mode="json")
            self._write_data_unlocked(data)
        return version

    def list_versions(self, architecture_id: str) -> list[ArchitectureVersionRecord]:
        data = self._read_data()
        versions = [
            ArchitectureVersionRecord.model_validate(item)
            for item in data["versions"].values()
            if item.get("architecture_id") == architecture_id
        ]
        return sorted(versions, key=lambda version: version.version_number)

    def append_event(self, event: CanvasEventRecord) -> CanvasEventRecord:
        with self._lock:
            data = self._read_data_unlocked()
            events = [
                CanvasEventRecord.model_validate(item)
                for item in data["events"].values()
                if item.get("architecture_id") == event.architecture_id
            ]
            for existing in events:
                if existing.idempotency_key == event.idempotency_key:
                    raise DuplicateIdempotencyError(existing)
            expected_sequence = max((item.sequence_number for item in events), default=0) + 1
            if event.sequence_number != expected_sequence:
                raise SequenceConflictError(f"Expected canvas event sequence {expected_sequence}")
            data["events"][event.event_id] = event.model_dump(mode="json")
            self._write_data_unlocked(data)
        return event

    def list_events(self, architecture_id: str) -> list[CanvasEventRecord]:
        data = self._read_data()
        events = [
            CanvasEventRecord.model_validate(item)
            for item in data["events"].values()
            if item.get("architecture_id") == architecture_id
        ]
        return sorted(events, key=lambda event: event.sequence_number)

    def create_snapshot(self, snapshot: CanvasSnapshotRecord) -> CanvasSnapshotRecord:
        with self._lock:
            data = self._read_data_unlocked()
            data["snapshots"][snapshot.snapshot_id] = snapshot.model_dump(mode="json")
            self._write_data_unlocked(data)
        return snapshot

    def latest_snapshot(self, architecture_id: str) -> Optional[CanvasSnapshotRecord]:
        data = self._read_data()
        snapshots = [
            CanvasSnapshotRecord.model_validate(item)
            for item in data["snapshots"].values()
            if item.get("architecture_id") == architecture_id
        ]
        snapshots.sort(key=lambda snapshot: (snapshot.sequence_number, snapshot.created_at), reverse=True)
        return snapshots[0] if snapshots else None

    def _read_data(self) -> dict:
        with self._lock:
            return self._read_data_unlocked()

    def _read_data_unlocked(self) -> dict:
        if not os.path.exists(self._db_path):
            return {"architectures": {}, "versions": {}, "events": {}, "snapshots": {}}
        with open(self._db_path, "r", encoding="utf-8") as file_handle:
            raw = file_handle.read().strip()
        if not raw:
            return {"architectures": {}, "versions": {}, "events": {}, "snapshots": {}}
        parsed = json.loads(raw)
        for key in ("architectures", "versions", "events", "snapshots"):
            parsed.setdefault(key, {})
        return parsed

    def _write_data(self, data: dict) -> None:
        with self._lock:
            self._write_data_unlocked(data)

    def _write_data_unlocked(self, data: dict) -> None:
        temp_path = f"{self._db_path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as file_handle:
            json.dump(data, file_handle, indent=2)
        os.replace(temp_path, self._db_path)

    @staticmethod
    def _is_within(root: str, candidate: str) -> bool:
        try:
            return os.path.commonpath([root, candidate]) == root
        except ValueError:
            return False


class SupabaseArchitectureStore:
    def __init__(self, supabase_url: str, service_role_key: str):
        self._client = create_client(supabase_url, service_role_key)

    def create_architecture(self, record: ArchitectureRecord) -> ArchitectureRecord:
        self._client.table("architectures").insert(self._architecture_row(record)).execute()
        return record

    def get_architecture(self, architecture_id: str) -> Optional[ArchitectureRecord]:
        response = self._client.table("architectures").select("*").eq("architecture_id", architecture_id).execute()
        rows = response.data or []
        return self._hydrate_architecture(rows[0]) if rows else None

    def list_architectures_for_user(self, user_id: str) -> list[ArchitectureRecord]:
        response = (
            self._client.table("architectures")
            .select("*")
            .eq("user_id", normalize_user_id(user_id))
            .order("updated_at", desc=True)
            .execute()
        )
        return [self._hydrate_architecture(row) for row in response.data or []]

    def update_architecture(self, record: ArchitectureRecord) -> ArchitectureRecord:
        self._client.table("architectures").update(self._architecture_row(record)).eq("architecture_id", record.architecture_id).execute()
        return record

    def create_version(self, version: ArchitectureVersionRecord) -> ArchitectureVersionRecord:
        row = version.model_dump(mode="json")
        row["user_id"] = normalize_user_id(version.user_id)
        row["blueprint"] = version.blueprint.model_dump(mode="json")
        self._client.table("architecture_versions").insert(row).execute()
        return version

    def list_versions(self, architecture_id: str) -> list[ArchitectureVersionRecord]:
        response = (
            self._client.table("architecture_versions")
            .select("*")
            .eq("architecture_id", architecture_id)
            .order("version_number")
            .execute()
        )
        return [self._hydrate_version(row) for row in response.data or []]

    def append_event(self, event: CanvasEventRecord) -> CanvasEventRecord:
        existing = (
            self._client.table("canvas_events")
            .select("*")
            .eq("architecture_id", event.architecture_id)
            .eq("idempotency_key", event.idempotency_key)
            .execute()
        )
        if existing.data:
            raise DuplicateIdempotencyError(self._hydrate_event(existing.data[0]))

        latest = (
            self._client.table("canvas_events")
            .select("sequence_number")
            .eq("architecture_id", event.architecture_id)
            .order("sequence_number", desc=True)
            .limit(1)
            .execute()
        )
        expected_sequence = ((latest.data or [{}])[0].get("sequence_number") or 0) + 1
        if event.sequence_number != expected_sequence:
            raise SequenceConflictError(f"Expected canvas event sequence {expected_sequence}")

        self._client.table("canvas_events").insert(self._event_row(event)).execute()
        return event

    def list_events(self, architecture_id: str) -> list[CanvasEventRecord]:
        response = (
            self._client.table("canvas_events")
            .select("*")
            .eq("architecture_id", architecture_id)
            .order("sequence_number")
            .execute()
        )
        return [self._hydrate_event(row) for row in response.data or []]

    def create_snapshot(self, snapshot: CanvasSnapshotRecord) -> CanvasSnapshotRecord:
        row = snapshot.model_dump(mode="json")
        row["user_id"] = normalize_user_id(snapshot.user_id)
        row["blueprint"] = snapshot.blueprint.model_dump(mode="json")
        self._client.table("canvas_snapshots").insert(row).execute()
        return snapshot

    def latest_snapshot(self, architecture_id: str) -> Optional[CanvasSnapshotRecord]:
        response = (
            self._client.table("canvas_snapshots")
            .select("*")
            .eq("architecture_id", architecture_id)
            .order("sequence_number", desc=True)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        return self._hydrate_snapshot(rows[0]) if rows else None

    @staticmethod
    def _architecture_row(record: ArchitectureRecord) -> dict:
        row = record.model_dump(mode="json")
        row["user_id"] = normalize_user_id(record.user_id)
        row["current_blueprint"] = record.current_blueprint.model_dump(mode="json")
        return row

    @staticmethod
    def _event_row(event: CanvasEventRecord) -> dict:
        row = event.model_dump(mode="json")
        row["user_id"] = normalize_user_id(event.user_id)
        row["operation"] = event.operation.model_dump(mode="json")
        row["validation_errors"] = [error.model_dump(mode="json") for error in event.validation_errors]
        return row

    @staticmethod
    def _hydrate_architecture(row: dict) -> ArchitectureRecord:
        return ArchitectureRecord.model_validate(row)

    @staticmethod
    def _hydrate_version(row: dict) -> ArchitectureVersionRecord:
        row = dict(row)
        row["blueprint"] = ArchitectureSpec.model_validate(row["blueprint"])
        return ArchitectureVersionRecord.model_validate(row)

    @staticmethod
    def _hydrate_event(row: dict) -> CanvasEventRecord:
        return CanvasEventRecord.model_validate(row)

    @staticmethod
    def _hydrate_snapshot(row: dict) -> CanvasSnapshotRecord:
        row = dict(row)
        row["blueprint"] = ArchitectureSpec.model_validate(row["blueprint"])
        return CanvasSnapshotRecord.model_validate(row)
