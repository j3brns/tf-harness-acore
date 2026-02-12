"""
Utility functions for Telemetry tracing.

Supports:
- OpenTelemetry (OTEL) via strands-agents[otel]
- Weave (optional) via deepresearch[weave]
"""

import base64
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

# Track initialization state
_telemetry_initialized = False
_weave_initialized = False


def initialize_telemetry() -> bool:
    """
    Initialize telemetry with available providers.

    Checks for OTEL configuration first, then optionally initializes Weave
    if installed and configured.

    Environment variables:
    - OTEL_EXPORTER_OTLP_ENDPOINT: OTLP endpoint URL
    - OTEL_EXPORTER_OTLP_HEADERS: Authorization headers
    - WEAVE_PROJECT: Weave project name (enables Weave if set)
    - ENABLE_WEAVE: Set to "true" to enable Weave (requires weave package)

    Returns:
        True if any telemetry was initialized, False if skipped.
    """
    global _telemetry_initialized

    if _telemetry_initialized:
        logger.debug("Telemetry already initialized, skipping")
        return True

    otel_ok = _initialize_otel()
    weave_ok = _initialize_weave()

    _telemetry_initialized = otel_ok or weave_ok

    if not _telemetry_initialized:
        logger.info("No telemetry configured (OTEL or Weave)")

    return _telemetry_initialized


def _initialize_otel() -> bool:
    """
    Initialize OpenTelemetry if configured.

    Returns:
        True if OTEL was initialized, False otherwise.
    """
    _configure_weave_otel_env()
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")

    if not endpoint:
        logger.debug("OTEL_EXPORTER_OTLP_ENDPOINT not set, skipping OTEL")
        return False

    try:
        from strands.telemetry import StrandsTelemetry

        strands_telemetry = StrandsTelemetry()
        strands_telemetry.setup_otlp_exporter()
        logger.info(f"OTEL telemetry initialized with endpoint: {endpoint}")
        return True
    except ImportError:
        logger.warning(
            "strands-agents[otel] not installed, skipping OTEL telemetry. "
            "Install with: pip install 'strands-agents[otel]'"
        )
        return False
    except Exception as e:
        logger.error(f"Failed to initialize OTEL telemetry: {e}")
        return False


def _configure_weave_otel_env() -> bool:
    """
    Configure OTEL env vars for Weave if not already set.

    Returns:
        True if OTEL env vars were set for Weave, False otherwise.
    """
    if "OTEL_EXPORTER_OTLP_ENDPOINT" in os.environ:
        return False

    api_key = os.environ.get("WANDB_API_KEY")
    project_id = os.environ.get("WEAVE_PROJECT")

    if not project_id:
        project_id = os.environ.get("WEAVE_PROJECT_ID")

    if not project_id:
        entity = os.environ.get("WANDB_ENTITY")
        project = os.environ.get("WANDB_PROJECT")
        if entity and project:
            project_id = f"{entity}/{project}"

    if not api_key or not project_id:
        return False

    base_url = os.environ.get("WANDB_BASE_URL", "https://trace.wandb.ai")
    os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = f"{base_url}/otel/v1/traces"

    auth_token = base64.b64encode(f"api:{api_key}".encode()).decode()
    os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = f"Authorization=Basic {auth_token},project_id={project_id}"
    return True


def _initialize_weave() -> bool:
    """
    Initialize Weave telemetry if configured and installed.

    Returns:
        True if Weave was initialized, False otherwise.
    """
    global _weave_initialized

    if _weave_initialized:
        return True

    # Check if Weave is enabled
    enable_weave = os.environ.get("ENABLE_WEAVE", "").lower() == "true"
    weave_project = os.environ.get("WEAVE_PROJECT")

    if not enable_weave and not weave_project:
        logger.debug("Weave not enabled (set ENABLE_WEAVE=true or WEAVE_PROJECT)")
        return False

    try:
        import weave

        project_name = weave_project or "deepresearch"
        weave.init(project_name)
        _weave_initialized = True
        logger.info(f"Weave telemetry initialized for project: {project_name}")
        return True
    except ImportError:
        logger.debug(
            "Weave not installed, skipping Weave telemetry. " "Install with: pip install 'deepresearch[weave]'"
        )
        return False
    except Exception as e:
        logger.warning(f"Failed to initialize Weave telemetry: {e}")
        return False


def get_trace_attributes(session_id: Optional[str] = None) -> dict:
    """
    Get trace attributes for telemetry.

    Args:
        session_id: Optional session ID to include in attributes.

    Returns:
        Dictionary of trace attributes.
    """
    attributes = {
        "service.name": "deepresearch",
        "agent.type": "deep-research",
    }

    if session_id:
        attributes["session.id"] = session_id

    return attributes
