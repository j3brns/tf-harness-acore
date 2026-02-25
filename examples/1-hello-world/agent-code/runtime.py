"""
Minimal Strands baseline demo agent (FAST-style parity).

This example intentionally keeps a small surface area:
- one Strands agent
- two local tools
- deterministic offline mode for local smoke tests
"""

import argparse
import json
import logging
import os
import re
from typing import Any

try:
    from bedrock_agentcore import BedrockAgentCoreApp
except ImportError:  # pragma: no cover - optional for local-only dry runs
    class BedrockAgentCoreApp:  # type: ignore[no-redef]
        """Minimal fallback used when the AgentCore SDK is not installed locally."""

        def __init__(self, debug: bool = False) -> None:
            self.debug = debug

        def entrypoint(self, func):
            return func

        def run(self) -> None:
            raise RuntimeError("bedrock-agentcore is not installed")


try:
    from strands import Agent, tool as strands_tool
except ImportError:  # pragma: no cover - tests cover the fallback path via monkeypatch
    Agent = None
    strands_tool = None


logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("hello_world_strands_baseline")


SYSTEM_PROMPT = (
    "You are a minimal Strands baseline demo agent. Keep answers concise, call tools when useful, "
    "and explain which example in this repo a user should start with."
)

DEFAULT_PROMPT = "What is 7 + 5? Also tell me when to use this example instead of deepresearch."

EXAMPLE_GUIDANCE = {
    "baseline": {
        "name": "1-hello-world",
        "summary": "Minimal Strands single-agent baseline for chat + tool flow parity demos.",
        "use_when": "You want the smallest runnable Strands example for local smoke tests or framework comparison.",
        "limitations": "No gateway, browser, memory, or multi-agent orchestration.",
    },
    "deepresearch": {
        "name": "3-deepresearch",
        "summary": "Advanced Strands DeepAgents workflow with planning, parallel research, and citations.",
        "use_when": "You need a production-style multi-agent research workflow.",
        "limitations": "Much larger dependency and configuration surface.",
    },
    "integrated": {
        "name": "5-integrated",
        "summary": "End-to-end Terraform composition with MCP servers and AgentCore deployment patterns.",
        "use_when": "You want full infrastructure composition and automatic MCP target wiring.",
        "limitations": "Not a minimal agent-code baseline; broader infra focus.",
    },
}


def _tool(func=None, **kwargs):
    """Use Strands @tool when available, otherwise return the function unchanged."""

    if strands_tool is None:
        if func is not None:
            return func

        def decorator(inner):
            return inner

        return decorator

    return strands_tool(func, **kwargs)


@_tool
def add_numbers(a: float, b: float) -> dict[str, Any]:
    """Return a small structured payload so tool output is easy to inspect."""

    total = a + b
    return {
        "operation": "add_numbers",
        "inputs": {"a": a, "b": b},
        "result": total,
        "expression": f"{a} + {b} = {total}",
    }


@_tool
def describe_repo_example(example: str) -> dict[str, str]:
    """Explain when to use this baseline vs larger examples."""

    key = example.strip().lower().replace("example ", "")
    aliases = {
        "1": "baseline",
        "1-hello-world": "baseline",
        "hello-world": "baseline",
        "hello world": "baseline",
        "baseline": "baseline",
        "strands baseline": "baseline",
        "3": "deepresearch",
        "3-deepresearch": "deepresearch",
        "deepresearch": "deepresearch",
        "deep research": "deepresearch",
        "5": "integrated",
        "5-integrated": "integrated",
        "integrated": "integrated",
    }
    resolved = aliases.get(key)
    if resolved is None:
        return {
            "error": f"Unknown example '{example}'",
            "known_examples": ", ".join(sorted(EXAMPLE_GUIDANCE.keys())),
        }
    return EXAMPLE_GUIDANCE[resolved]


def build_agent(model: str | None = None):
    """Create the minimal Strands agent used in live mode."""

    if Agent is None:
        raise RuntimeError("strands-agents is not installed")

    return Agent(
        model=model or os.getenv("STRANDS_MODEL"),
        tools=[add_numbers, describe_repo_example],
        system_prompt=SYSTEM_PROMPT,
        name="hello-world-strands-baseline",
        description="Minimal Strands single-agent baseline demo",
    )


def _extract_result_text(result: Any) -> str:
    """Best-effort conversion of a Strands AgentResult into plain text."""

    message = getattr(result, "message", None)
    if isinstance(message, str):
        return message

    if message is not None:
        content = getattr(message, "content", None)
        if isinstance(content, list):
            text_chunks: list[str] = []
            for block in content:
                if isinstance(block, dict):
                    if isinstance(block.get("text"), str):
                        text_chunks.append(block["text"])
                    elif isinstance(block.get("text", {}).get("text"), str):
                        text_chunks.append(block["text"]["text"])
                else:
                    block_text = getattr(block, "text", None)
                    if isinstance(block_text, str):
                        text_chunks.append(block_text)
                    elif isinstance(getattr(block_text, "text", None), str):
                        text_chunks.append(block_text.text)
            if text_chunks:
                return "\n".join(text_chunks)

        if hasattr(message, "to_dict"):
            message_dict = message.to_dict()
            if isinstance(message_dict, dict):
                for block in message_dict.get("content", []):
                    if isinstance(block, dict) and isinstance(block.get("text"), str):
                        return block["text"]

        return str(message)

    if hasattr(result, "to_dict"):
        return json.dumps(result.to_dict(), default=str)

    return str(result)


def _coerce_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "on"}
    return bool(value)


def _detect_addition(prompt: str) -> tuple[float, float] | None:
    match = re.search(r"(-?\d+(?:\.\d+)?)\s*(?:\+|plus)\s*(-?\d+(?:\.\d+)?)", prompt, flags=re.IGNORECASE)
    if not match:
        return None
    return float(match.group(1)), float(match.group(2))


def _detect_example_queries(prompt: str) -> list[str]:
    lowered = prompt.lower()
    matches: list[str] = []
    if "hello world" in lowered or "baseline" in lowered or "1-hello-world" in lowered:
        matches.append("baseline")
    if "deepresearch" in lowered or "deep research" in lowered:
        matches.append("deepresearch")
    if "integrated" in lowered or "5-integrated" in lowered:
        matches.append("integrated")
    return matches


def run_offline_demo(prompt: str) -> dict[str, Any]:
    """
    Deterministic local baseline flow.

    This is the default local mode so the example is runnable without AWS/model credentials.
    """

    tool_calls: list[dict[str, Any]] = []
    response_lines: list[str] = []

    addition = _detect_addition(prompt)
    if addition is not None:
        tool_output = add_numbers(addition[0], addition[1])
        tool_calls.append({"tool": "add_numbers", "arguments": {"a": addition[0], "b": addition[1]}, "output": tool_output})
        response_lines.append(f"Sum: {tool_output['result']}")

    example_keys = _detect_example_queries(prompt)
    for example_key in example_keys:
        tool_output = describe_repo_example(example_key)
        tool_calls.append({"tool": "describe_repo_example", "arguments": {"example": example_key}, "output": tool_output})
        if "error" not in tool_output:
            response_lines.append(
                f"{tool_output['name']}: {tool_output['summary']} Use when: {tool_output['use_when']}"
            )

    if not response_lines:
        response_lines.append(
            "Minimal Strands baseline demo is running in offline mode. Try a prompt like "
            "'What is 7 + 5?' or ask when to use deepresearch vs integrated."
        )

    return {
        "status": "success",
        "framework": "strands",
        "mode": "offline-demo",
        "prompt": prompt,
        "tool_calls": tool_calls,
        "result": "\n".join(response_lines),
    }


def run_live_agent(prompt: str) -> dict[str, Any]:
    """Call the real Strands agent (requires model configuration/credentials)."""

    agent = build_agent()
    result = agent(prompt)
    payload: dict[str, Any] = {
        "status": "success",
        "framework": "strands",
        "mode": "live",
        "prompt": prompt,
        "result": _extract_result_text(result),
    }
    if hasattr(result, "to_dict"):
        payload["raw_result"] = result.to_dict()
    return payload


app = BedrockAgentCoreApp(debug=False)


@app.entrypoint
def invoke(payload: dict[str, Any], context: Any = None) -> dict[str, Any]:
    """AgentCore entrypoint for the minimal Strands baseline demo."""

    del context  # unused in this minimal baseline

    request = payload or {}
    prompt = str(request.get("prompt") or request.get("message") or DEFAULT_PROMPT)

    # Default local behavior is offline for reproducible smoke tests.
    live_requested = _coerce_bool(request.get("live")) or os.getenv("STRANDS_BASELINE_MODE", "").lower() == "live"
    offline_requested = _coerce_bool(request.get("offline")) or not live_requested

    logger.info("Invoking minimal Strands baseline (mode=%s)", "offline-demo" if offline_requested else "live")

    try:
        if offline_requested:
            return run_offline_demo(prompt)
        return run_live_agent(prompt)
    except Exception as exc:  # pragma: no cover - exercised indirectly via tests using monkeypatch
        logger.exception("Strands baseline invocation failed")
        return {
            "status": "error",
            "framework": "strands",
            "mode": "live" if live_requested else "offline-demo",
            "prompt": prompt,
            "message": str(exc),
            "hint": "Use offline mode for local smoke checks: python runtime.py --offline",
        }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Legacy-compatible wrapper used by local tests."""

    return invoke(event or {}, context)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the minimal Strands baseline demo agent locally.")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT, help="Prompt for the demo agent.")
    parser.add_argument("--live", action="store_true", help="Use real Strands agent invocation (requires credentials/model).")
    parser.add_argument("--offline", action="store_true", help="Force deterministic offline demo mode (default).")
    args = parser.parse_args()

    response = handler({"prompt": args.prompt, "live": args.live, "offline": args.offline or not args.live}, None)
    print(json.dumps(response, indent=2, default=str))
    return 0 if response.get("status") == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
