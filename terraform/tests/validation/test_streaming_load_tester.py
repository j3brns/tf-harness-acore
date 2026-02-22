from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from unittest.mock import patch


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "streaming_load_tester.py"
    spec = importlib.util.spec_from_file_location("streaming_load_tester", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def test_build_default_prompt_mentions_duration_and_heartbeat():
    prompt = mod.build_default_prompt(900, 15)
    assert "900 seconds" in prompt
    assert "15 seconds" in prompt
    assert "long-running mock tool" in prompt


def test_resolve_target_url_uses_api_output_and_appends_chat():
    outputs = {"agentcore_bff_api_url": {"value": "https://abc.execute-api.us-east-1.amazonaws.com/dev"}}
    with patch.object(mod, "read_terraform_outputs", return_value=outputs):
        url = mod.resolve_target_url(None, use_spa_url=False)
    assert url == "https://abc.execute-api.us-east-1.amazonaws.com/dev/chat"


def test_resolve_target_url_uses_spa_output_and_appends_api_chat():
    outputs = {"agentcore_bff_spa_url": {"value": "https://d111111abcdef8.cloudfront.net"}}
    with patch.object(mod, "read_terraform_outputs", return_value=outputs):
        url = mod.resolve_target_url(None, use_spa_url=True)
    assert url == "https://d111111abcdef8.cloudfront.net/api/chat"


def test_update_metrics_from_ndjson_events_tracks_meta_and_delta():
    metrics = mod.RunMetrics(requested_session_id="test")

    event_type, payload = mod.parse_ndjson_line(b'{"type":"meta","sessionId":"sess-1"}\n')
    mod.update_metrics_from_event(metrics, event_type, payload)

    event_type, payload = mod.parse_ndjson_line(b'{"type":"delta","delta":"hello"}\n')
    mod.update_metrics_from_event(metrics, event_type, payload)

    assert metrics.meta_events == 1
    assert metrics.delta_events == 1
    assert metrics.delta_chars == 5
    assert metrics.runtime_session_id == "sess-1"


def test_evaluate_result_fails_short_stream_and_non_ndjson():
    thresholds = mod.Thresholds(
        min_stream_seconds=900.0,
        min_delta_events=1,
        require_ndjson=True,
        fail_on_error_event=True,
    )
    config = mod.RequestConfig(
        url="https://example.test/chat",
        prompt="x",
        duration_seconds=900,
        socket_timeout_seconds=930.0,
        headers={},
        insecure=False,
        thresholds=thresholds,
    )
    metrics = mod.RunMetrics(
        status_code=200,
        content_type="application/json",
        requested_session_id="sess",
        duration_seconds=12.3,
        delta_events=0,
        error_events=1,
    )

    reasons = mod.evaluate_result(config, metrics, exception=None)

    assert any("content-type" in reason for reason in reasons)
    assert any("closed early" in reason for reason in reasons)
    assert any("insufficient delta" in reason for reason in reasons)
    assert any("error event" in reason for reason in reasons)


def test_build_summary_aggregates_pass_fail_and_stats():
    ok = mod.RunResult(
        worker_id=1,
        iteration=1,
        request_id="r1",
        passed=True,
        reasons=[],
        metrics=mod.RunMetrics(
            status_code=200,
            requested_session_id="a",
            duration_seconds=10.0,
            delta_events=2,
            bytes_received=100,
        ),
        exception=None,
    )
    bad = mod.RunResult(
        worker_id=1,
        iteration=2,
        request_id="r2",
        passed=False,
        reasons=["x"],
        metrics=mod.RunMetrics(
            status_code=500,
            requested_session_id="b",
            duration_seconds=3.0,
            delta_events=0,
            bytes_received=10,
        ),
        exception="HTTPError 500",
    )

    summary = mod.build_summary([ok, bad])

    assert summary["total_requests"] == 2
    assert summary["passed"] == 1
    assert summary["failed"] == 1
    assert summary["status_counts"] == {"200": 1, "500": 1}
    assert summary["duration_seconds"]["max"] == 10.0
