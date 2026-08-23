"""
Tests for SafeWorkspaceRunner path validation.
"""

import os
import tempfile

import pytest

from app.services.workspace_runner import _verify_workspace
from app.config import settings


# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------

def test_verify_workspace_accepts_valid_path():
    """A path inside BUILD_STORAGE_ROOT should be accepted and returned canonicalized."""
    trusted_root = os.path.abspath(settings.BUILD_STORAGE_ROOT)
    child = os.path.join(trusted_root, "users", "u1", "projects", "p1", "runs", "r1")
    # Should not raise
    result = _verify_workspace(child)
    assert os.path.isabs(result)


def test_verify_workspace_rejects_path_outside_root():
    """A path outside the trusted root must be rejected."""
    outside_path = os.path.join(tempfile.gettempdir(), "escape_attempt")
    with pytest.raises(ValueError, match="escapes the trusted build root|outside trusted root"):
        _verify_workspace(outside_path)


def test_verify_workspace_rejects_traversal():
    """Path traversal via '..' must be blocked."""
    trusted_root = os.path.abspath(settings.BUILD_STORAGE_ROOT)
    traversal = os.path.join(trusted_root, "users", "u1", "..", "..", "..", "etc", "passwd")
    with pytest.raises(ValueError):
        _verify_workspace(traversal)


def test_verify_workspace_accepts_root_itself():
    """The trusted root itself is a valid workspace."""
    result = _verify_workspace(settings.BUILD_STORAGE_ROOT)
    assert os.path.isabs(result)
