"""Smoke and unit tests for the LangGraph baseline runtime."""

from datetime import datetime


def test_build_graph_compiles_and_invokes():
    """The graph should compile and run without network calls."""
    from runtime import build_graph

    graph = build_graph()
    result = graph.invoke({"prompt": "What can you do?"})

    assert result["intent"] == "capabilities"
    assert "response" in result
    assert result["steps"] == ["normalize_prompt", "collect_capabilities", "compose_response"]


def test_run_agent_returns_structured_result():
    """run_agent should return framework metadata and steps."""
    from runtime import run_agent

    result = run_agent("What can you do?")

    assert result["framework"] == "langgraph"
    assert result["intent"] == "capabilities"
    assert "LangGraph baseline capabilities" in result["response"]
    assert len(result["capabilities"]) >= 1
    assert result["steps"][-1] == "compose_response"


def test_handler_accepts_prompt(sample_event):
    """handler should return a success payload for a standard prompt."""
    from runtime import handler

    result = handler(sample_event, None)

    assert result["status"] == "success"
    assert result["message"] == "LangGraph baseline completed"
    assert result["result"]["framework"] == "langgraph"
    assert result["result"]["intent"] == "capabilities"


def test_handler_accepts_query_alias():
    """handler should accept the query alias used by other examples."""
    from runtime import handler

    result = handler({"query": "hello there"}, None)

    assert result["status"] == "success"
    assert result["result"]["intent"] == "echo"
    assert "hello there" in result["result"]["response"].lower()


def test_handler_uses_default_prompt():
    """handler should use a default prompt when none is provided."""
    from runtime import handler

    result = handler({}, None)

    assert result["status"] == "success"
    assert result["result"]["intent"] == "capabilities"


def test_handler_returns_iso_timestamp(sample_event):
    """handler response should contain an ISO8601 UTC timestamp."""
    from runtime import handler

    result = handler(sample_event, None)

    assert result["timestamp"].endswith("Z")
    datetime.fromisoformat(result["timestamp"].replace("Z", "+00:00"))


def test_handler_error_path(monkeypatch):
    """handler should return a structured error when run_agent fails."""
    import runtime

    def _raise(*args, **kwargs):
        del args, kwargs
        raise RuntimeError("boom")

    monkeypatch.setattr(runtime, "run_agent", _raise)
    result = runtime.handler({"prompt": "fail"}, None)

    assert result["status"] == "error"
    assert "boom" in result["message"]


def test_agentcore_app_exposes_runtime_methods():
    """BedrockAgentCoreApp instance should expose the expected runtime hooks."""
    from runtime import app

    assert callable(app.entrypoint)
    assert callable(app.run)
