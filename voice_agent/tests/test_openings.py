import pytest

from agent import get_greeting_for_mode, get_resume_opening_instructions


@pytest.mark.parametrize(
    ("mode", "expected_phrases"),
    [
        ("general", ("what is on your mind",)),
        ("debate", ("strongest argument", "weak spots")),
        ("brainstorm", ("something bold",)),
        ("build", ("shape the plan", "before we touch the code")),
    ],
)
def test_fresh_openings_sound_conversational_and_mode_specific(mode, expected_phrases):
    greeting = get_greeting_for_mode(mode).lower()

    for phrase in expected_phrases:
        assert phrase in greeting
    assert greeting.endswith("?")


@pytest.mark.parametrize("mode", ["general", "debate", "brainstorm", "build"])
def test_resume_opening_uses_history_and_preserves_mode(mode):
    instructions = get_resume_opening_instructions(mode).lower()

    assert "restored conversation" in instructions
    assert "specific" in instructions
    assert "one natural question" in instructions
    assert mode in instructions
