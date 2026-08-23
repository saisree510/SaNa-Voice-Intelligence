"""Provider-neutral abstract interface for coding-agent execution."""

from abc import ABC, abstractmethod
from typing import AsyncGenerator

from app.models.build_models import BuildRunEvent, BuildSpec


class CodingAgentAdapter(ABC):
    """
    Abstract base for all coding-agent providers.

    Implementations:
      - DeepCodeRuntimeAdapter  — verified DeepCode CLI execution
      - PrototypeScaffoldAdapter — labelled fixed-file scaffold fallback

    Soul's Build Service depends only on this interface, never on a
    concrete provider. Every BuildRun records `provider_label` so users
    can always see which provider generated their files.
    """

    @property
    @abstractmethod
    def provider_label(self) -> str:
        """Human-readable provider name recorded on every BuildRun."""
        ...

    @abstractmethod
    async def run(
        self,
        spec: BuildSpec,
        run_id: str,
    ) -> AsyncGenerator[BuildRunEvent, None]:
        """
        Execute the build described by `spec` and stream `BuildRunEvent` objects
        until completion or error.

        Implementations must:
        - Yield a `start` event as the first emission.
        - Yield a `complete` or `error` event as the final emission.
        - Never suppress exceptions silently; re-raise after yielding an `error` event.
        - Always write files inside `spec.workspace_path`.
        """
        ...

    @abstractmethod
    async def cancel(self, run_id: str) -> None:
        """Request graceful cancellation of a running build."""
        ...


__all__ = ["CodingAgentAdapter"]
