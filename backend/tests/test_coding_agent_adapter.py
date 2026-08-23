"""
Tests for the CodingAgentAdapter contract and PrototypeScaffoldAdapter.
"""

import asyncio
import os
import tempfile
from datetime import datetime, timezone

import pytest

from app.adapters.coding_agent_adapter import CodingAgentAdapter
from app.adapters.deepcode_adapter import PrototypeScaffoldAdapter
from app.models.build_models import BuildRunEvent, BuildSpec


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_spec(workspace: str, spec: str = "Build a hello-world app") -> BuildSpec:
    return BuildSpec(
        run_id="test-run-001",
        project_id="proj-test",
        specification=spec,
        workspace_path=workspace,
        approved_by="user-test",
    )


async def _collect(gen) -> list[BuildRunEvent]:
    events = []
    async for evt in gen:
        events.append(evt)
    return events


# ---------------------------------------------------------------------------
# CodingAgentAdapter contract
# ---------------------------------------------------------------------------

def test_prototype_scaffold_is_coding_agent_adapter():
    """PrototypeScaffoldAdapter must satisfy the CodingAgentAdapter interface."""
    adapter = PrototypeScaffoldAdapter()
    assert isinstance(adapter, CodingAgentAdapter)


def test_prototype_scaffold_provider_label():
    adapter = PrototypeScaffoldAdapter()
    assert adapter.provider_label == "prototype_scaffold"


def test_prototype_scaffold_has_cancel():
    adapter = PrototypeScaffoldAdapter()
    assert callable(adapter.cancel)


# ---------------------------------------------------------------------------
# PrototypeScaffoldAdapter run behaviour
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_scaffold_generates_files():
    with tempfile.TemporaryDirectory() as workspace:
        adapter = PrototypeScaffoldAdapter()
        spec = _make_spec(workspace)
        events = await _collect(adapter.run(spec, spec.run_id))

        assert len(events) >= 2, "Expected at least start + complete events"
        assert events[0].event_type == "start"
        assert events[-1].event_type == "complete"

        # Files must exist in workspace
        generated = os.listdir(workspace)
        assert "main.py" in generated or "README.md" in generated


@pytest.mark.asyncio
async def test_scaffold_all_events_have_correct_provider():
    with tempfile.TemporaryDirectory() as workspace:
        adapter = PrototypeScaffoldAdapter()
        spec = _make_spec(workspace)
        events = await _collect(adapter.run(spec, spec.run_id))
        for evt in events:
            assert evt.provider == "prototype_scaffold"


@pytest.mark.asyncio
async def test_scaffold_events_have_sequential_sequence_numbers():
    with tempfile.TemporaryDirectory() as workspace:
        adapter = PrototypeScaffoldAdapter()
        spec = _make_spec(workspace)
        events = await _collect(adapter.run(spec, spec.run_id))
        seqs = [e.sequence for e in events]
        assert seqs == list(range(1, len(seqs) + 1)), "Sequence numbers must be contiguous starting at 1"


@pytest.mark.asyncio
async def test_scaffold_complete_event_lists_files():
    with tempfile.TemporaryDirectory() as workspace:
        adapter = PrototypeScaffoldAdapter()
        spec = _make_spec(workspace)
        events = await _collect(adapter.run(spec, spec.run_id))
        complete_evt = events[-1]
        assert complete_evt.event_type == "complete"
        assert "generated_files" in complete_evt.details
        assert len(complete_evt.details["generated_files"]) > 0


@pytest.mark.asyncio
async def test_scaffold_run_id_is_propagated():
    with tempfile.TemporaryDirectory() as workspace:
        adapter = PrototypeScaffoldAdapter()
        spec = _make_spec(workspace)
        events = await _collect(adapter.run(spec, "custom-run-42"))
        for evt in events:
            assert evt.run_id == "custom-run-42"


@pytest.mark.asyncio
async def test_scaffold_cancel_is_noop():
    """cancel() on the scaffold adapter must not raise."""
    adapter = PrototypeScaffoldAdapter()
    await adapter.cancel("any-run-id")  # must not raise


# ---------------------------------------------------------------------------
# BuildSpec
# ---------------------------------------------------------------------------

def test_build_spec_prompt_contains_specification():
    with tempfile.TemporaryDirectory() as workspace:
        spec = _make_spec(workspace, spec="Build a REST API for todo items")
        prompt = spec.to_prompt()
        assert "REST API for todo items" in prompt


def test_build_spec_prompt_contains_workspace():
    with tempfile.TemporaryDirectory() as workspace:
        spec = _make_spec(workspace)
        prompt = spec.to_prompt()
        assert workspace in prompt


def test_build_spec_blueprint_hash_is_none_without_blueprint():
    with tempfile.TemporaryDirectory() as workspace:
        spec = _make_spec(workspace)
        assert spec.blueprint_hash() is None


def test_build_spec_blueprint_hash_is_stable():
    with tempfile.TemporaryDirectory() as workspace:
        spec = _make_spec(workspace)
        # Two calls with no blueprint both return None and are stable
        assert spec.blueprint_hash() == spec.blueprint_hash()
