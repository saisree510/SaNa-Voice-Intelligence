"""Registers the DeepCode LLM connection at process startup.

DeepCode stores its named connections under `~/.deepcode/` (or `$DEEPCODE_HOME`),
which lives outside Railway's persistent volume (BUILD_STORAGE_ROOT) and is
therefore wiped on every redeploy/restart. This must run once per process start
so `deepcode exec --connection <DEEPCODE_CONNECTION>` has a connection to resolve.
The actual API key never passes through here or through DeepCode's config file —
`--api-key-env` tells DeepCode to read it from the named environment variable at
call time.
"""

import logging
import os
import shutil
import subprocess

from app.config import settings

logger = logging.getLogger("backend.deepcode_provider_setup")

# Reflects whether the connection registered below is actually usable, distinct
# from whether the DeepCode binary is merely present (see build_router.coding_adapter).
provider_registered = False
provider_registration_error: str | None = None


def ensure_deepcode_provider_registered() -> None:
    global provider_registered, provider_registration_error

    if not settings.DEEPCODE_ENABLED:
        provider_registration_error = "DEEPCODE_ENABLED is false"
        return

    binary = shutil.which(settings.DEEPCODE_BINARY_PATH)
    if binary is None:
        provider_registration_error = f"binary '{settings.DEEPCODE_BINARY_PATH}' not found on PATH"
        logger.warning(
            "DEEPCODE_ENABLED=True but %s; skipping provider registration.",
            provider_registration_error,
        )
        return

    if not os.environ.get(settings.DEEPCODE_API_KEY_ENV):
        provider_registration_error = f"{settings.DEEPCODE_API_KEY_ENV} is not set"
        logger.warning(
            "DEEPCODE_ENABLED=True but %s; skipping provider registration. "
            "Builds will fail over to the Prototype Scaffold until this key is configured.",
            provider_registration_error,
        )
        return

    try:
        init_result = subprocess.run(
            [binary, "init"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if init_result.returncode != 0:
            provider_registration_error = f"`deepcode init` failed: {init_result.stderr.strip()}"
            logger.error(provider_registration_error)
            return

        set_result = subprocess.run(
            [
                binary, "provider", "set", settings.DEEPCODE_CONNECTION,
                "--template", settings.DEEPCODE_PROVIDER_TEMPLATE,
                "--api-key-env", settings.DEEPCODE_API_KEY_ENV,
            ],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if set_result.returncode != 0:
            provider_registration_error = (
                f"`deepcode provider set {settings.DEEPCODE_CONNECTION}` failed: {set_result.stderr.strip()}"
            )
            logger.error(provider_registration_error)
            return

        provider_registered = True
        provider_registration_error = None
        logger.info("DeepCode connection '%s' registered.", settings.DEEPCODE_CONNECTION)
    except (subprocess.TimeoutExpired, OSError) as exc:
        provider_registration_error = f"DeepCode provider registration failed: {exc}"
        logger.error(provider_registration_error)


__all__ = ["ensure_deepcode_provider_registered", "provider_registered", "provider_registration_error"]
