"""AIService abstraction.

Architecture (per spec): Mobile App -> FastAPI -> Chat Service -> Mode
Prompt -> AIService -> AI Provider. Routes and chat_service.py never
call an AI SDK directly — only through get_ai_provider() below, so the
provider is swappable without touching either.

Two providers:
- MockAIProvider: canned, mode-flavored responses, no network calls at
  all. Used by the test suite and available any time via AI_PROVIDER=mock.
- LiveKitInferenceProvider: real LLM calls via LiveKit Inference,
  reusing the LiveKit credentials already configured for voice — no
  separate AI provider account needed. Default (AI_PROVIDER=livekit).
"""

import random
from abc import ABC, abstractmethod
from functools import lru_cache

from ..core.config import get_settings
from ..modes import MODE_CHAT_INSTRUCTIONS
from .build_tools import BUILD_MODE_TOOLS

# Guards against a pathological loop where the model keeps calling
# tools and never produces a final answer.
_MAX_TOOL_ROUNDS = 5


class AIServiceError(Exception):
    """Base class for all AI-provider failures the chat service should handle."""


class AITimeoutError(AIServiceError):
    pass


class AIUnexpectedResponseError(AIServiceError):
    pass


class AIProvider(ABC):
    @abstractmethod
    async def generate_reply(self, *, mode: str, history: list[dict[str, str]], user_message: str) -> str:
        """[history] is prior turns as [{"role": "user"|"assistant", "content": str}, ...],
        oldest first, not including [user_message]. Returns SANA's reply text.
        Raises an AIServiceError subclass on failure — never lets a raw
        provider exception escape.
        """
        raise NotImplementedError


class MockAIProvider(AIProvider):
    """No network calls — deterministic enough to assert on in tests,
    varied enough to not look broken in manual testing.
    """

    _TEMPLATES: dict[str, list[str]] = {
        'debate': [
            'I would push back on that. What is the strongest evidence for "{msg}", and have you considered the case against it?',
            'That is one view, but it skips a real counterpoint. What happens if the opposite of "{msg}" is true?',
            'I will grant part of that, but it sounds stronger than the evidence supports. What would actually change your mind here?',
        ],
        'brainstorm': [
            'Good starting point. A few directions from "{msg}": go narrower and pick one audience, or combine it with something adjacent. Which pulls at you?',
            'I like that. What is the version of this that is 10x simpler, and what would you cut to get there?',
            'That opens up a few paths. What is the constraint you are least willing to compromise on here?',
        ],
        'build': [
            'Got it. Before I structure this — who is this actually for, and what is the one thing it must do well on day one?',
            'Makes sense. Is this mobile, web, or both, and does it need accounts, or can it start anonymous?',
            'That is a clear core. What is the smallest version of "{msg}" you could actually ship first?',
        ],
    }

    async def generate_reply(self, *, mode: str, history: list[dict[str, str]], user_message: str) -> str:
        templates = self._TEMPLATES.get(mode, self._TEMPLATES['build'])
        template = random.choice(templates)
        return template.format(msg=user_message[:120])


class LiveKitInferenceProvider(AIProvider):
    """Real LLM responses via LiveKit Inference — see module docstring."""

    def __init__(self, model: str) -> None:
        self._model = model

    async def generate_reply(self, *, mode: str, history: list[dict[str, str]], user_message: str) -> str:
        # Imported lazily so MockAIProvider (and anything importing this
        # module just for the AIProvider type) never needs livekit-agents
        # available, and so tests using the mock provider stay fast.
        from livekit.agents import APIConnectionError, APIError, APITimeoutError
        from livekit.agents.inference import LLM
        from livekit.agents.llm import ChatContext, ToolContext, execute_function_call

        instructions = MODE_CHAT_INSTRUCTIONS.get(mode)
        if instructions is None:
            raise AIUnexpectedResponseError(f"Unknown mode '{mode}'.")

        chat_ctx = ChatContext.empty()
        chat_ctx.add_message(role='system', content=instructions)
        for turn in history:
            role = turn.get('role')
            content = turn.get('content', '')
            if role in ('user', 'assistant') and content:
                chat_ctx.add_message(role=role, content=content)
        chat_ctx.add_message(role='user', content=user_message)

        # File-access tools (read-only sana_app/sana_backend source) are
        # only offered in Build mode — see build_tools.py.
        tools = BUILD_MODE_TOOLS if mode == 'build' else []
        tool_ctx = ToolContext(tools=tools) if tools else None

        llm = LLM(model=self._model)
        try:
            for _ in range(_MAX_TOOL_ROUNDS):
                response = await llm.chat(chat_ctx=chat_ctx, tools=tools or None).collect()

                if not response.tool_calls:
                    if not response.text or not response.text.strip():
                        raise AIUnexpectedResponseError('The AI provider returned an empty response.')
                    return response.text.strip()

                assert tool_ctx is not None  # tool_calls only possible when tools were offered
                for tool_call in response.tool_calls:
                    result = await execute_function_call(tool_call, tool_ctx)
                    chat_ctx.insert(result.fnc_call)
                    if result.fnc_call_out:
                        chat_ctx.insert(result.fnc_call_out)

            raise AIUnexpectedResponseError('SANA used too many tool calls without finishing a reply.')
        except APITimeoutError as e:
            raise AITimeoutError('The AI provider took too long to respond.') from e
        except (APIConnectionError, APIError) as e:
            raise AIServiceError(f'AI provider error: {e}') from e
        finally:
            await llm.aclose()


@lru_cache
def get_ai_provider() -> AIProvider:
    settings = get_settings()
    if settings.ai_provider == 'mock':
        return MockAIProvider()
    return LiveKitInferenceProvider(model=settings.ai_model)
