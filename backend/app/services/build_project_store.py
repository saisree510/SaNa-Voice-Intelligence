import json
import os
import re
from threading import Lock
from typing import Iterable, Optional

from app.models.deepcode_models import BuildProjectModel


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

    def default_workspace_path(self, title: str, project_id: str) -> str:
        slug = re.sub(r'[^a-zA-Z0-9_-]', '_', title.lower()).strip('_') or project_id
        candidate = os.path.join(self.trusted_folder(), f'{slug}_{project_id}')
        return self.validate_workspace_path(candidate)

    def validate_workspace_path(self, candidate_path: str) -> str:
        normalized = os.path.abspath(os.path.normpath(candidate_path))
        trusted = self.trusted_folder()
        if not self._is_within(trusted, normalized):
            raise ValueError(f'Workspace path must stay inside trusted build root: {trusted}')
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

    def list_projects_for_user(self, user_id: str, is_dev_user: bool) -> list[BuildProjectModel]:
        data = self._read_data()
        projects = [BuildProjectModel.model_validate(item) for item in data.values()]
        if not is_dev_user:
            projects = [project for project in projects if project.user_id == user_id]
        return sorted(projects, key=lambda project: project.updated_at, reverse=True)

    def find_latest_project_for_user(
        self,
        user_id: str,
        is_dev_user: bool,
        *,
        statuses: Optional[Iterable[str]] = None,
    ) -> Optional[BuildProjectModel]:
        projects = self.list_projects_for_user(user_id=user_id, is_dev_user=is_dev_user)
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
