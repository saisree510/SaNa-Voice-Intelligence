from .brainstorm import BRAINSTORM_BEHAVIOR, BRAINSTORM_INSTRUCTIONS
from .build import BUILD_BEHAVIOR, BUILD_INSTRUCTIONS, BUILD_TOOLS_NOTE
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
