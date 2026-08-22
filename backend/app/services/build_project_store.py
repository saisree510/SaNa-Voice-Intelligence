import json
import os
import re
from threading import Lock
from typing import Iterable, Optional

from supabase import create_client

from app.auth.auth_bearer import normalize_user_id, user_id_aliases
from app.models.deepcode_models import BuildFileModel, BuildProjectModel, BuildRunTurnModel, DeepCodeEvent


class BuildProjectStore:
    def __init__(self, trusted_root: str, db_path: Optional[str] = None):
        self._trusted_root = os.path.abspath(os.path.normpath(trusted_root))
        self._db_path = os.path.abspath(os.path.normpath(db_path or os.path.join(self._trusted_root, '.sana_build_projects.json')))
        self._lock = Lock()
        os.makedirs(self._trusted_root, exist_ok=True)
        if not self._is_within(self._trusted_root, self._db_path):
            raise ValueError('Project database path must stay within the trusted build root')
        if not os.path.exists(self._db_path):
            self._write_data({})

    def trusted_folder(self) -> str:
        os.makedirs(self._trusted_root, exist_ok=True)
        return self._trusted_root

    def db_path(self) -> str:
        return self._db_path

    def user_workspace_root(self, user_id: str) -> str:
        normalized_user = normalize_user_id(user_id)
        safe_user = re.sub(r'[^a-zA-Z0-9_-]', '_', normalized_user).strip('_')
        if not safe_user:
            raise ValueError('Authenticated user id is required for build storage')
        root = os.path.join(self.trusted_folder(), 'users', safe_user)
        os.makedirs(root, exist_ok=True)
        return root

    def default_workspace_path(self, title: str, project_id: str, user_id: str) -> str:
        slug = re.sub(r'[^a-zA-Z0-9_-]', '_', title.lower()).strip('_') or project_id
        candidate = os.path.join(self.user_workspace_root(user_id), f'{slug}_{project_id}')
        return self.validate_user_workspace_path(user_id, candidate)

    def validate_workspace_path(self, candidate_path: str) -> str:
        normalized = os.path.abspath(os.path.normpath(candidate_path))
        trusted = self.trusted_folder()
        if not self._is_within(trusted, normalized):
            raise ValueError(f'Workspace path must stay inside trusted build root: {trusted}')
        return normalized

    def validate_user_workspace_path(self, user_id: str, candidate_path: str) -> str:
        normalized = self.validate_workspace_path(candidate_path)
        user_root = self.user_workspace_root(user_id)
        if not self._is_within(user_root, normalized):
            raise ValueError('Workspace path must stay inside the authenticated user build folder')
        return normalized

    def get_project(self, project_id: str) -> Optional[BuildProjectModel]:
        data = self._read_data()
        project = data.get(project_id)
        if not project:
            return None
        return BuildProjectModel.model_validate(project)

    def find_project_by_session_id(self, session_id: str) -> Optional[BuildProjectModel]:
        data = self._read_data()
        for project in data.values():
            if project.get('session_id') == session_id:
                return BuildProjectModel.model_validate(project)
        return None

    def list_projects_for_user(self, user_id: str) -> list[BuildProjectModel]:
        data = self._read_data()
        projects = [BuildProjectModel.model_validate(item) for item in data.values()]
        aliases = user_id_aliases(user_id)
        projects = [project for project in projects if project.user_id in aliases]
        return sorted(projects, key=lambda project: project.updated_at, reverse=True)

    def find_latest_project_for_user(
        self,
        user_id: str,
        *,
        statuses: Optional[Iterable[str]] = None,
    ) -> Optional[BuildProjectModel]:
        projects = self.list_projects_for_user(user_id=user_id)
        if statuses is not None:
            allowed_statuses = {status for status in statuses}
            projects = [project for project in projects if project.status in allowed_statuses]
        return projects[0] if projects else None

    def claim_legacy_dev_projects_for_user(self, user_id: str) -> list[BuildProjectModel]:
        claimed: list[BuildProjectModel] = []
        with self._lock:
            data = self._read_data_unlocked()
            updated = False
            for project_id, item in data.items():
                if not isinstance(item, dict):
                    continue
                if item.get('user_id') != 'dev-user-0000':
                    continue
                workspace_path = item.get('workspace_path')
                if not isinstance(workspace_path, str):
                    continue
                try:
                    self.validate_workspace_path(workspace_path)
                except ValueError:
                    continue
                item['user_id'] = user_id
                data[project_id] = item
                updated = True
                claimed.append(BuildProjectModel.model_validate(item))
            if updated:
                self._write_data_unlocked(data)
        return sorted(claimed, key=lambda project: project.updated_at, reverse=True)

    def upsert_project(self, project: BuildProjectModel) -> None:
        with self._lock:
            data = self._read_data_unlocked()
            data[project.project_id] = project.model_dump(mode='json')
            self._write_data_unlocked(data)

    def _read_data(self) -> dict:
        with self._lock:
            return self._read_data_unlocked()

    def _read_data_unlocked(self) -> dict:
        if not os.path.exists(self._db_path):
            return {}
        with open(self._db_path, 'r', encoding='utf-8') as file_handle:
            raw = file_handle.read().strip()
        if not raw:
            return {}
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
        if isinstance(parsed, list):
            migrated: dict[str, dict] = {}
            for item in parsed:
                if isinstance(item, dict) and isinstance(item.get('project_id'), str):
                    migrated[item['project_id']] = item
            return migrated
        return {}

    def _write_data(self, data: dict) -> None:
        with self._lock:
            self._write_data_unlocked(data)

    def _write_data_unlocked(self, data: dict) -> None:
        os.makedirs(os.path.dirname(self._db_path), exist_ok=True)
        temp_path = f'{self._db_path}.tmp'
        with open(temp_path, 'w', encoding='utf-8') as file_handle:
            json.dump(data, file_handle, indent=2)
        os.replace(temp_path, self._db_path)

    @staticmethod
    def _is_within(root: str, candidate: str) -> bool:
        try:
            return os.path.commonpath([root, candidate]) == root
        except ValueError:
            return False


class SupabaseBuildProjectStore:
    """Durable Build Mode metadata store backed by Supabase.

    Workspace files remain under the trusted build root. This store persists the
    metadata needed to reopen and authorize a project after a Railway restart.
    """

    def __init__(self, trusted_root: str, supabase_url: str, service_role_key: str):
        self._trusted_root = os.path.abspath(os.path.normpath(trusted_root))
        self._client = create_client(supabase_url, service_role_key)
        os.makedirs(self._trusted_root, exist_ok=True)

    def trusted_folder(self) -> str:
        os.makedirs(self._trusted_root, exist_ok=True)
        return self._trusted_root

    def user_workspace_root(self, user_id: str) -> str:
        normalized_user = normalize_user_id(user_id)
        safe_user = re.sub(r'[^a-zA-Z0-9_-]', '_', normalized_user).strip('_')
        if not safe_user:
            raise ValueError('Authenticated user id is required for build storage')
        root = os.path.join(self.trusted_folder(), 'users', safe_user)
        os.makedirs(root, exist_ok=True)
        return root

    def default_workspace_path(self, title: str, project_id: str, user_id: str) -> str:
        slug = re.sub(r'[^a-zA-Z0-9_-]', '_', title.lower()).strip('_') or project_id
        candidate = os.path.join(self.user_workspace_root(user_id), f'{slug}_{project_id}')
        return self.validate_user_workspace_path(user_id, candidate)

    def validate_workspace_path(self, candidate_path: str) -> str:
        normalized = os.path.abspath(os.path.normpath(candidate_path))
        trusted = self.trusted_folder()
        if not BuildProjectStore._is_within(trusted, normalized):
            raise ValueError(f'Workspace path must stay inside trusted build root: {trusted}')
        return normalized

    def validate_user_workspace_path(self, user_id: str, candidate_path: str) -> str:
        normalized = self.validate_workspace_path(candidate_path)
        user_root = self.user_workspace_root(user_id)
        if not BuildProjectStore._is_within(user_root, normalized):
            raise ValueError('Workspace path must stay inside the authenticated user build folder')
        return normalized

    def get_project(self, project_id: str) -> Optional[BuildProjectModel]:
        response = (
            self._client.table('build_projects')
            .select('*')
            .eq('project_id', project_id)
            .execute()
        )
        rows = response.data or []
        return self._hydrate_project(rows[0]) if rows else None

    def find_project_by_session_id(self, session_id: str) -> Optional[BuildProjectModel]:
        response = (
            self._client.table('build_projects')
            .select('*')
            .eq('session_id', session_id)
            .execute()
        )
        rows = response.data or []
        return self._hydrate_project(rows[0]) if rows else None

    def list_projects_for_user(self, user_id: str) -> list[BuildProjectModel]:
        normalized_user = normalize_user_id(user_id)
        response = (
            self._client.table('build_projects')
            .select('*')
            .eq('user_id', normalized_user)
            .order('updated_at', desc=True)
            .execute()
        )
        return [self._hydrate_project(row) for row in response.data or []]

    def find_latest_project_for_user(
        self,
        user_id: str,
        *,
        statuses: Optional[Iterable[str]] = None,
    ) -> Optional[BuildProjectModel]:
        projects = self.list_projects_for_user(user_id)
        if statuses is not None:
            allowed_statuses = set(statuses)
            projects = [project for project in projects if project.status in allowed_statuses]
        return projects[0] if projects else None

    def claim_legacy_dev_projects_for_user(self, user_id: str) -> list[BuildProjectModel]:
        # Legacy JSON records are deliberately quarantined rather than claimed.
        return []

    def upsert_project(self, project: BuildProjectModel) -> None:
        project_row = project.model_dump(mode='json', exclude={'history', 'generated_files'})
        project_row['user_id'] = normalize_user_id(project.user_id)
        self._client.table('build_projects').upsert(project_row, on_conflict='project_id').execute()

        # A project model is authoritative for its child metadata. Replace the
        # recorded run/file projection as one bounded update to avoid duplicates.
        self._client.table('build_files').delete().eq('project_id', project.project_id).execute()
        self._client.table('build_runs').delete().eq('project_id', project.project_id).execute()

        for run in project.history:
            run_row = self._build_run_row(run, project.user_id)
            self._client.table('build_runs').upsert(run_row, on_conflict='run_id').execute()

            event_rows = [
                {
                    'run_id': run.turn_id,
                    'project_id': project.project_id,
                    'user_id': normalize_user_id(event.user_id or project.user_id),
                    'sequence_no': index,
                    'event_type': event.event_type,
                    'message': event.message,
                    'details': event.details,
                    'event_timestamp': event.timestamp,
                }
                for index, event in enumerate(run.events)
            ]
            if event_rows:
                self._client.table('build_run_events').insert(event_rows).execute()

        file_rows = [
            {
                'project_id': file.project_id,
                'run_id': file.run_id,
                'user_id': normalize_user_id(file.user_id),
                'path': file.path,
            }
            for file in project.generated_files
        ]
        if file_rows:
            self._client.table('build_files').insert(file_rows).execute()

    @staticmethod
    def _build_run_row(run: BuildRunTurnModel, project_user_id: str) -> dict:
        row = run.model_dump(mode='json', exclude={'events'})
        # The API model preserves the legacy `turn_id` field, while the
        # normalized persistence table calls the same identifier `run_id`.
        row['run_id'] = row.pop('turn_id')
        row['user_id'] = normalize_user_id(run.user_id or project_user_id)
        return row

    def _hydrate_project(self, project_row: dict) -> BuildProjectModel:
        project_id = project_row['project_id']
        runs_response = (
            self._client.table('build_runs')
            .select('*')
            .eq('project_id', project_id)
            .order('created_at')
            .execute()
        )
        runs = runs_response.data or []
        run_ids = [run['run_id'] for run in runs]
        events_by_run: dict[str, list[DeepCodeEvent]] = {run_id: [] for run_id in run_ids}
        if run_ids:
            events_response = (
                self._client.table('build_run_events')
                .select('*')
                .in_('run_id', run_ids)
                .order('sequence_no')
                .execute()
            )
            for event in events_response.data or []:
                events_by_run.setdefault(event['run_id'], []).append(
                    DeepCodeEvent(
                        event_type=event['event_type'],
                        timestamp=event['event_timestamp'],
                        message=event['message'],
                        details=event.get('details'),
                        user_id=event.get('user_id'),
                        project_id=event.get('project_id'),
                        session_id=next(
                            (run['session_id'] for run in runs if run['run_id'] == event['run_id']),
                            None,
                        ),
                    )
                )

        files_response = (
            self._client.table('build_files')
            .select('*')
            .eq('project_id', project_id)
            .execute()
        )
        return BuildProjectModel(
            **project_row,
            history=[
                BuildRunTurnModel(
                    turn_id=run['run_id'],
                    project_id=run['project_id'],
                    session_id=run['session_id'],
                    user_id=run.get('user_id'),
                    prompt=run['prompt'],
                    status=run['status'],
                    events=events_by_run.get(run['run_id'], []),
                    created_at=run['created_at'],
                )
                for run in runs
            ],
            generated_files=[
                BuildFileModel(
                    path=file['path'],
                    user_id=file['user_id'],
                    project_id=file['project_id'],
                    run_id=file['run_id'],
                )
                for file in files_response.data or []
            ],
        )
