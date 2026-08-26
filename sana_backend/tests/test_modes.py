"""Tests for the small dynamic context helpers in app/modes/__init__.py
-- pure functions, no network/DB, fast to test directly.
"""

from app.modes import current_datetime_note, user_name_note


def test_current_datetime_note_mentions_the_actual_year():
    # Not asserting an exact string (it changes every minute) -- just
    # that it's really using datetime.now(), not a hardcoded stub.
    from datetime import datetime, timezone

    note = current_datetime_note()
    assert str(datetime.now(timezone.utc).year) in note
    assert 'UTC' in note


def test_user_name_note_includes_the_given_name():
    note = user_name_note('Ada')
    assert 'Ada' in note


def test_user_name_note_is_empty_for_no_name():
    # Not-yet-onboarded / pre-this-feature accounts have no name --
    # appending '' must be a safe no-op wherever this is called.
    assert user_name_note(None) == ''
    assert user_name_note('') == ''
