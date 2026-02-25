"""
Smoke tests for the minimal Strands baseline example.
"""

from types import SimpleNamespace


class TestOfflineDemoMode:
    def test_handler_offline_addition_flow(self, addition_prompt):
        from runtime import handler

        result = handler({"prompt": addition_prompt, "offline": True}, None)

        assert result["status"] == "success"
        assert result["framework"] == "strands"
        assert result["mode"] == "offline-demo"
        assert "Sum: 12.0" in result["result"]
        assert any(call["tool"] == "add_numbers" for call in result["tool_calls"])

    def test_handler_offline_example_guidance_flow(self, comparison_prompt):
        from runtime import handler

        result = handler({"prompt": comparison_prompt, "offline": True}, None)

        assert result["status"] == "success"
        assert any(call["tool"] == "describe_repo_example" for call in result["tool_calls"])
        assert "3-deepresearch" in result["result"]

    def test_handler_defaults_to_offline_for_local_smoke(self):
        from runtime import handler

        result = handler({}, None)

        assert result["status"] == "success"
        assert result["mode"] == "offline-demo"
        assert result["framework"] == "strands"


class TestHandler:
    """
    Backward-compatible smoke test name for the SDK compatibility matrix harness.

    The harness currently targets this exact node id for Example 1.
    """

    def test_handler_success_with_buckets(self):
        from runtime import handler

        result = handler({"prompt": "What is 2 + 3?", "offline": True}, None)

        assert result["status"] == "success"
        assert result["framework"] == "strands"
        assert any(call["tool"] == "add_numbers" for call in result["tool_calls"])


class TestAgentConstruction:
    def test_build_agent_uses_strands_constructor(self, monkeypatch):
        import runtime

        calls = {}

        class FakeAgent:
            def __init__(self, **kwargs):
                calls["kwargs"] = kwargs

        monkeypatch.setattr(runtime, "Agent", FakeAgent)

        built = runtime.build_agent(model="demo-model")

        assert isinstance(built, FakeAgent)
        assert calls["kwargs"]["model"] == "demo-model"
        assert calls["kwargs"]["name"] == "hello-world-strands-baseline"
        assert len(calls["kwargs"]["tools"]) == 2
        assert "baseline demo" in calls["kwargs"]["description"]

    def test_live_mode_returns_actionable_error_when_strands_missing(self, monkeypatch):
        import runtime

        monkeypatch.setattr(runtime, "Agent", None)

        result = runtime.invoke({"prompt": "hello", "live": True}, None)

        assert result["status"] == "error"
        assert result["framework"] == "strands"
        assert result["mode"] == "live"
        assert "offline" in result["hint"].lower()


class TestResultExtraction:
    def test_extract_result_text_from_message_content(self):
        from runtime import _extract_result_text

        fake_message = SimpleNamespace(content=[{"text": "hello from strands"}])
        fake_result = SimpleNamespace(message=fake_message)

        assert _extract_result_text(fake_result) == "hello from strands"

    def test_extract_result_text_falls_back_to_string(self):
        from runtime import _extract_result_text

        fake_result = SimpleNamespace(message=SimpleNamespace(content=None))

        assert "namespace" in _extract_result_text(fake_result)
