"""Tests for the read-only file-access layer Build mode's AI tools use
(app/services/file_access.py). Tests the pure functions directly —
no LLM call, no network, fast and deterministic.
"""

import pytest

from app.services.file_access import (
    FileAccessError,
    list_directory,
    read_file_contents,
    resolve_safe_path,
)


def test_can_list_a_real_backend_directory():
    result = list_directory('sana_backend/app/modes')
    assert 'debate.py' in result
    assert 'build.py' in result


def test_can_read_a_real_backend_file():
    content = read_file_contents('sana_backend/app/modes/debate.py')
    assert 'DEBATE_BEHAVIOR' in content


def test_rejects_unknown_project_name():
    with pytest.raises(FileAccessError):
        resolve_safe_path('etc/passwd')


def test_rejects_path_traversal_out_of_project_root():
    with pytest.raises(FileAccessError):
        resolve_safe_path('sana_backend/../../../Windows/System32')


def test_rejects_env_file():
    with pytest.raises(FileAccessError):
        resolve_safe_path('sana_backend/.env')


def test_rejects_database_file():
    with pytest.raises(FileAccessError):
        resolve_safe_path('sana_backend/sana.db')


def test_rejects_venv_contents():
    with pytest.raises(FileAccessError):
        resolve_safe_path('sana_backend/.venv/pyvenv.cfg')


def test_rejects_git_internals():
    with pytest.raises(FileAccessError):
        resolve_safe_path('sana_backend/.git/config')


def test_denylisted_entries_are_hidden_from_directory_listing():
    entries = list_directory('sana_backend').splitlines()
    # Exact-entry checks, not substring — '.env.example' legitimately
    # contains '.env' as a substring and should stay visible.
    assert '.env' not in entries
    assert '.venv/' not in entries
    assert 'sana.db' not in entries
    assert '.env.example' in entries  # confirms this ISN'T over-broad


def test_reading_a_directory_as_a_file_is_rejected():
    with pytest.raises(FileAccessError):
        read_file_contents('sana_backend/app')


def test_listing_a_file_as_a_directory_is_rejected():
    with pytest.raises(FileAccessError):
        list_directory('sana_backend/app/main.py')


def test_reading_a_nonexistent_file_is_rejected():
    with pytest.raises(FileAccessError):
        read_file_contents('sana_backend/app/does_not_exist.py')


def test_can_access_sana_app_too():
    result = list_directory('sana_app/lib')
    assert 'main.dart' in result
