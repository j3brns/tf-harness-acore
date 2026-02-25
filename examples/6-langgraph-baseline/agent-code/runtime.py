"""
Minimal LangGraph baseline demo for Bedrock AgentCore runtime.

This example intentionally avoids live LLM calls so it can run locally without
credentials while still demonstrating LangGraph graph construction and
AgentCore runtime entrypoint wiring.
"""

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any, TypedDict

from bedrock_agentcore import BedrockAgentCoreApp
from langgraph.graph import END, START, StateGraph

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("langgraph_baseline")


class DemoState(TypedDict, total=False):
    """Mutable graph state for the demo workflow."""

    prompt: str
    normalized_prompt: str
    intent: str
    capabilities: list[str]
    response: str
    steps: list[str]


def normalize_prompt(state: DemoState) -> DemoState:
    """Normalize incoming prompt text and infer a simple intent."""
    prompt = (state.get("prompt") or "").strip()
    normalized = " ".join(prompt.split())
    lowered = normalized.lower()
    intent = "capabilities" if any(word in lowered for word in ("can", "capabilities", "help")) else "echo"
    return {
        "normalized_prompt": normalized or "Hello from LangGraph baseline",
        "intent": intent,
        "steps": [*(state.get("steps") or []), "normalize_prompt"],
    }


def collect_capabilities(state: DemoState) -> DemoState:
    """Return a small deterministic capability set (tool-like node)."""
    intent = state.get("intent", "echo")
    if intent == "capabilities":
        capabilities = [
            "Deterministic LangGraph node orchestration",
            "Bedrock AgentCore runtime entrypoint wiring",
            "Structured JSON responses for local smoke tests",
        ]
    else:
        capabilities = ["Prompt normalization", "State tracking", "Response composition"]
    return {
        "capabilities": capabilities,
        "steps": [*(state.get("steps") or []), "collect_capabilities"],
    }


def compose_response(state: DemoState) -> DemoState:
    """Compose the final user-facing response."""
    prompt = state.get("normalized_prompt", "")
    intent = state.get("intent", "echo")
    capabilities = state.get("capabilities", [])
    if intent == "capabilities":
        lines = [f"- {item}" for item in capabilities]
        response = "LangGraph baseline capabilities:\n" + "\n".join(lines)
    else:
        response = f"LangGraph baseline received: {prompt}"

    return {
        "response": response,
        "steps": [*(state.get("steps") or []), "compose_response"],
    }


def build_graph():
    """Compile the minimal LangGraph workflow."""
    graph = StateGraph(DemoState)
    graph.add_node("normalize_prompt", normalize_prompt)
    graph.add_node("collect_capabilities", collect_capabilities)
    graph.add_node("compose_response", compose_response)
    graph.add_edge(START, "normalize_prompt")
    graph.add_edge("normalize_prompt", "collect_capabilities")
    graph.add_edge("collect_capabilities", "compose_response")
    graph.add_edge("compose_response", END)
    return graph.compile()


GRAPH = build_graph()
app = BedrockAgentCoreApp(debug=True)


def run_agent(prompt: str) -> dict[str, Any]:
    """Invoke the compiled graph and return structured output."""
    state = GRAPH.invoke({"prompt": prompt})
    return {
        "framework": "langgraph",
        "intent": state.get("intent", "unknown"),
        "steps": state.get("steps", []),
        "response": state.get("response", ""),
        "capabilities": state.get("capabilities", []),
    }


@app.entrypoint
def invoke(payload: dict[str, Any], context: Any = None) -> dict[str, Any]:
    """AgentCore runtime entrypoint."""
    del context  # Unused in this minimal baseline.

    logger.info("LangGraph baseline invoked")
    logger.info("Payload keys: %s", sorted((payload or {}).keys()))

    try:
        prompt = (
            (payload or {}).get("prompt")
            or (payload or {}).get("message")
            or (payload or {}).get("query")
            or "What can you do?"
        )
        result = run_agent(prompt=prompt)
        return {
            "status": "success",
            "message": "LangGraph baseline completed",
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "result": result,
        }
    except Exception as exc:
        logger.exception("LangGraph baseline failed")
        return {
            "status": "error",
            "message": f"LangGraph baseline failed: {exc}",
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Compatibility wrapper mirroring the simpler example handlers."""
    return invoke(event, context)


if __name__ == "__main__":
    sample = {"prompt": "What capabilities does this LangGraph demo show?"}
    print(json.dumps(handler(sample, None), indent=2))
