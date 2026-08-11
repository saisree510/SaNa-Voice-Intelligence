from datetime import datetime, timezone

from .brainstorm import BRAINSTORM_BEHAVIOR, BRAINSTORM_INSTRUCTIONS
from .build import BUILD_BEHAVIOR, BUILD_INSTRUCTIONS, BUILD_TOOLS_NOTE, BUILD_VOICE_TOOLS_NOTE
from .debate import DEBATE_BEHAVIOR, DEBATE_INSTRUCTIONS
from .text_style import TEXT_OUTPUT_RULES

# Single source of truth for valid mode ids. Matches the `AppMode.id`
# values in the Flutter app's app_modes.dart — keep the two in sync if
# a mode is ever renamed.
VALID_MODES: tuple[str, ...] = ('debate', 'brainstorm', 'build')

_BEHAVIOR: dict[str, str] = {
    'debate': DEBATE_BEHAVIOR,
    'brainstorm': BRAINSTORM_BEHAVIOR,
    'build': BUILD_BEHAVIOR,
}

# Voice instructions (behavior + voice output rules) — used by
# agent/voice_agent.py. Unchanged name/shape from before this file was
# split, so the voice agent's import didn't need to change.
MODE_INSTRUCTIONS: dict[str, str] = {
    'debate': DEBATE_INSTRUCTIONS,
    'brainstorm': BRAINSTORM_INSTRUCTIONS,
    'build': BUILD_INSTRUCTIONS,
}
# Build's voice variant only — mentions the one tool voice actually has
# wired up (build_project). Debate/brainstorm are untouched.
MODE_INSTRUCTIONS['build'] += BUILD_VOICE_TOOLS_NOTE

# Text-chat instructions (same behavior + text output rules instead of
# voice's) — used by the /chat/message endpoint. Same underlying
# behavior as voice, different formatting constraints (e.g. Build mode
# can emit code blocks here; voice explicitly forbids that).
MODE_CHAT_INSTRUCTIONS: dict[str, str] = {
    mode_id: behavior + TEXT_OUTPUT_RULES for mode_id, behavior in _BEHAVIOR.items()
}
# Build's text-chat variant only — see BUILD_TOOLS_NOTE's docstring for why.
MODE_CHAT_INSTRUCTIONS['build'] += BUILD_TOOLS_NOTE

OPENING_LINES: dict[str, str] = {
    'debate': "I'm ready to debate. Bring me a claim or a position — I'll challenge it.",
    'brainstorm': "Tell me an idea, even a rough one, and let's build on it together.",
    'build': "Tell me what you want to build, and I'll help turn it into a plan.",
}


def current_datetime_note() -> str:
    """A fresh "here's the actual date/time" line for the system prompt.

    Deliberately *not* baked into MODE_INSTRUCTIONS/MODE_CHAT_INSTRUCTIONS
    above — those are plain module-level strings, computed once at
    import time (server startup), so anything appended there would be
    frozen at whatever moment the process happened to start and go
    stale from then on. Call this fresh per request instead (both
    ai_service.py and voice_agent.py do) so it's always current.

    Without this, the model has no way to know the date or time at
    all — it isn't a fact in its training data, and nothing else in
    the app ever told it -- confirmed by testing: asked directly, it
    said exactly that.

    UTC, not the caller's local time zone: the backend has no reliable
    way to know a given user's zone today (no timezone travels with a
    chat/voice request). Correct-and-labeled beats silently wrong.
    """
    now = datetime.now(timezone.utc)
    return (
        f'\n# Current date and time\n'
        f"Right now it is {now.strftime('%A, %B %d, %Y, %H:%M')} UTC. "
        'Use this if asked about the date, time, day of the week, or how long until/since something — '
        'you have no other way to know it. If the user seems to be in a different time zone, say the '
        "time is in UTC rather than guessing theirs."
    )


def user_name_note(name: str | None) -> str:
    """A "here's who you're talking to" line for the system prompt —
    same reasoning as current_datetime_note: without something telling
    the model, it has no way to know. Before the name was persisted
    server-side (see users.name / PATCH /auth/me), this fact only ever
    lived in the Flutter app's local storage and never reached the
    model at all, in either text chat or voice.

    Returns '' (nothing to add) when there's no name yet — a signed-up-
    but-not-yet-onboarded account, or an older account from before this
    field existed. Appending an empty string is a safe no-op wherever
    this is called from.
    """
    if not name:
        return ''
    return (
        f'\n# Who you are talking to\n'
        f"The user's name is {name}. You already know this — don't ask for it. "
        "Use it when it feels natural (e.g. a greeting), not in every single reply."
    )
