#!/usr/bin/env python3
"""Streaming load/soak tester for BFF -> AgentCore streaming paths.

Issue #32 goal:
- Automate verification of long-lived streaming connectivity (up to 900s)
- Exercise the NDJSON streaming contract used by the BFF proxy
- Provide machine-usable pass/fail exit codes for CI/manual validation evidence

This utility is intentionally stdlib-only.
"""

from __future__ import annotations

import argparse
import json
import logging
import socket
import ssl
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path


LOGGER = logging.getLogger("streaming_load_tester")


@dataclass(slots=True)
class Thresholds:
    min_stream_seconds: float
    min_delta_events: int
    require_ndjson: bool
    fail_on_error_event: bool


@dataclass(slots=True)
class RequestConfig:
    url: str
    prompt: str
    duration_seconds: int
    socket_timeout_seconds: float
    headers: dict[str, str]
    insecure: bool
    thresholds: Thresholds


@dataclass(slots=True)
class RunMetrics:
    status_code: int | None = None
    content_type: str = ""
    runtime_session_id: str | None = None
    requested_session_id: str = ""
    duration_seconds: float = 0.0
    ttfb_seconds: float | None = None
    bytes_received: int = 0
    line_count: int = 0
    meta_events: int = 0
    delta_events: int = 0
    error_events: int = 0
    unknown_events: int = 0
    json_parse_errors: int = 0
    delta_chars: int = 0


@dataclass(slots=True)
class RunResult:
    worker_id: int
    iteration: int
    request_id: str
    passed: bool
    reasons: list[str]
    metrics: RunMetrics
    exception: str | None = None


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def read_terraform_outputs() -> dict:
    tf_dir = repo_root() / "terraform"
    try:
        raw = subprocess.check_output(["terraform", "output", "-json"], cwd=tf_dir, stderr=subprocess.STDOUT)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        if isinstance(exc, FileNotFoundError):
            raise RuntimeError("terraform executable not found in PATH") from exc
        raise RuntimeError(
            "failed to read terraform outputs from terraform/; "
            "run from a deployed worktree or pass --url explicitly.\n"
            f"terraform output: {exc.output.decode(errors='replace').strip()}"
        ) from exc

    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("terraform output -json returned invalid JSON") from exc


def _append_default_path(base_url: str, default_path: str, force_append: bool = False) -> str:
    parsed = urllib.parse.urlparse(base_url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"unsupported URL scheme for endpoint: {base_url}")
    path = parsed.path or ""
    if path in ("", "/"):
        path = default_path
    elif force_append and not path.endswith(default_path):
        path = f"{path.rstrip('/')}{default_path}"
    rebuilt = parsed._replace(path=path, params="", query="", fragment="")
    return urllib.parse.urlunparse(rebuilt)


def resolve_target_url(explicit_url: str | None, use_spa_url: bool) -> str:
    if explicit_url:
        default_path = "/api/chat" if use_spa_url else "/chat"
        return _append_default_path(explicit_url, default_path, force_append=False)

    outputs = read_terraform_outputs()
    output_name = "agentcore_bff_spa_url" if use_spa_url else "agentcore_bff_api_url"
    value = ((outputs.get(output_name) or {}).get("value") or "").strip()
    if not value:
        raise RuntimeError(f"terraform output '{output_name}' is empty; pass --url explicitly")
    default_path = "/api/chat" if use_spa_url else "/chat"
    return _append_default_path(value, default_path, force_append=True)


def build_default_prompt(duration_seconds: int, heartbeat_seconds: int) -> str:
    return (
        "Invoke the long-running mock tool and keep this response stream open for "
        f"{duration_seconds} seconds. Emit a short progress update every {heartbeat_seconds} "
        "seconds so the client can verify the streaming connection stays alive. "
        "At the end, emit a completion message with the total elapsed seconds."
    )


def build_headers(args: argparse.Namespace) -> dict[str, str]:
    headers: dict[str, str] = {
        "content-type": "application/json",
        "accept": "application/x-ndjson, application/json",
        "user-agent": "agentcore-streaming-load-tester/0.1",
    }

    if args.cookie_header:
        headers["Cookie"] = args.cookie_header
    elif args.session_cookie:
        if "session_id=" in args.session_cookie:
            headers["Cookie"] = args.session_cookie
        else:
            headers["Cookie"] = f"session_id={args.session_cookie}"

    if args.bearer_token:
        headers["Authorization"] = f"Bearer {args.bearer_token}"

    for raw_header in args.header or []:
        if ":" not in raw_header:
            raise ValueError(f"invalid header '{raw_header}' (expected 'Name: Value')")
        name, value = raw_header.split(":", 1)
        name = name.strip()
        value = value.strip()
        if not name:
            raise ValueError(f"invalid header '{raw_header}' (empty name)")
        headers[name] = value

    return headers


def parse_ndjson_line(raw_line: bytes) -> tuple[str | None, dict | None]:
    line = raw_line.decode("utf-8", errors="replace").strip()
    if not line:
        return None, None
    payload = json.loads(line)
    event_type = payload.get("type") if isinstance(payload, dict) else None
    return event_type, payload if isinstance(payload, dict) else None


def update_metrics_from_event(metrics: RunMetrics, event_type: str | None, payload: dict | None) -> None:
    if event_type is None:
        return
    if event_type == "meta":
        metrics.meta_events += 1
        session_id = (payload or {}).get("sessionId")
        if isinstance(session_id, str) and session_id:
            metrics.runtime_session_id = session_id
        return
    if event_type == "delta":
        metrics.delta_events += 1
        delta = (payload or {}).get("delta")
        if isinstance(delta, str):
            metrics.delta_chars += len(delta)
        return
    if event_type == "error":
        metrics.error_events += 1
        return
    metrics.unknown_events += 1


def evaluate_result(config: RequestConfig, metrics: RunMetrics, exception: str | None) -> list[str]:
    reasons: list[str] = []
    if exception:
        reasons.append(f"request exception: {exception}")
        return reasons

    if metrics.status_code != 200:
        reasons.append(f"unexpected HTTP status {metrics.status_code}")

    if config.thresholds.require_ndjson and "application/x-ndjson" not in (metrics.content_type or "").lower():
        reasons.append(f"unexpected content-type '{metrics.content_type or '<missing>'}'")

    if metrics.duration_seconds < config.thresholds.min_stream_seconds:
        reasons.append(
            f"stream closed early ({metrics.duration_seconds:.2f}s < {config.thresholds.min_stream_seconds:.2f}s)"
        )

    if metrics.delta_events < config.thresholds.min_delta_events:
        reasons.append(f"insufficient delta events ({metrics.delta_events} < {config.thresholds.min_delta_events})")

    if config.thresholds.fail_on_error_event and metrics.error_events > 0:
        reasons.append(f"received {metrics.error_events} error event(s)")

    return reasons


def make_ssl_context(insecure: bool) -> ssl.SSLContext | None:
    if not insecure:
        return None
    return ssl._create_unverified_context()  # noqa: SLF001 - stdlib helper for controlled opt-in CLI behavior


def perform_request(config: RequestConfig, worker_id: int, iteration: int, session_id: str) -> RunResult:
    request_id = f"w{worker_id}-i{iteration}-{uuid.uuid4().hex[:8]}"
    metrics = RunMetrics(requested_session_id=session_id)
    body = json.dumps({"prompt": config.prompt, "sessionId": session_id}).encode("utf-8")
    headers = dict(config.headers)
    req = urllib.request.Request(config.url, data=body, headers=headers, method="POST")
    ssl_context = make_ssl_context(config.insecure)
    started = time.monotonic()
    exception_text: str | None = None

    LOGGER.debug("[%s] POST %s", request_id, config.url)

    try:
        with urllib.request.urlopen(req, timeout=config.socket_timeout_seconds, context=ssl_context) as response:
            metrics.status_code = getattr(response, "status", None) or response.getcode()
            metrics.content_type = response.headers.get("content-type", "")
            runtime_header = response.headers.get("x-amzn-bedrock-agentcore-runtime-session-id")
            if runtime_header:
                metrics.runtime_session_id = runtime_header
            metrics.ttfb_seconds = time.monotonic() - started

            while True:
                raw_line = response.readline()
                if not raw_line:
                    break
                metrics.bytes_received += len(raw_line)
                metrics.line_count += 1

                try:
                    event_type, payload = parse_ndjson_line(raw_line)
                except json.JSONDecodeError:
                    metrics.json_parse_errors += 1
                    continue

                update_metrics_from_event(metrics, event_type, payload)

    except urllib.error.HTTPError as exc:
        metrics.status_code = exc.code
        metrics.content_type = exc.headers.get("content-type", "") if exc.headers else ""
        try:
            raw = exc.read()
        except Exception:  # pragma: no cover - defensive
            raw = b""
        if raw:
            metrics.bytes_received += len(raw)
        exception_text = f"HTTPError {exc.code}"
    except urllib.error.URLError as exc:
        exception_text = f"URLError: {exc.reason}"
    except socket.timeout:
        exception_text = f"socket timeout after {config.socket_timeout_seconds}s"
    except Exception as exc:  # pragma: no cover - defensive
        exception_text = f"{type(exc).__name__}: {exc}"
    finally:
        metrics.duration_seconds = time.monotonic() - started

    reasons = evaluate_result(config, metrics, exception_text)
    passed = not reasons

    return RunResult(
        worker_id=worker_id,
        iteration=iteration,
        request_id=request_id,
        passed=passed,
        reasons=reasons,
        metrics=metrics,
        exception=exception_text,
    )


def build_summary(results: list[RunResult]) -> dict:
    durations = [r.metrics.duration_seconds for r in results]
    deltas = [r.metrics.delta_events for r in results]
    bytes_rx = [r.metrics.bytes_received for r in results]
    status_counts: dict[str, int] = {}
    failures = 0
    for result in results:
        key = str(result.metrics.status_code)
        status_counts[key] = status_counts.get(key, 0) + 1
        if not result.passed:
            failures += 1

    summary = {
        "total_requests": len(results),
        "passed": len(results) - failures,
        "failed": failures,
        "duration_seconds": {
            "min": min(durations) if durations else 0.0,
            "max": max(durations) if durations else 0.0,
            "avg": statistics.fmean(durations) if durations else 0.0,
        },
        "delta_events": {
            "min": min(deltas) if deltas else 0,
            "max": max(deltas) if deltas else 0,
            "avg": statistics.fmean(deltas) if deltas else 0.0,
        },
        "bytes_received": {
            "min": min(bytes_rx) if bytes_rx else 0,
            "max": max(bytes_rx) if bytes_rx else 0,
            "avg": statistics.fmean(bytes_rx) if bytes_rx else 0.0,
        },
        "status_counts": status_counts,
        "results": [asdict(r) for r in results],
    }
    return summary


def worker_runner(
    worker_id: int,
    iterations: int,
    config: RequestConfig,
    session_id_prefix: str,
    stagger_seconds: float,
) -> list[RunResult]:
    results: list[RunResult] = []
    if stagger_seconds > 0 and worker_id > 1:
        delay = stagger_seconds * (worker_id - 1)
        LOGGER.info("[worker %s] staggering start by %.2fs", worker_id, delay)
        time.sleep(delay)

    for iteration in range(1, iterations + 1):
        session_id = f"{session_id_prefix}-w{worker_id}-i{iteration}-{uuid.uuid4().hex[:6]}"
        LOGGER.info("[worker %s/%s] starting request %s", worker_id, iterations, iteration)
        result = perform_request(config, worker_id=worker_id, iteration=iteration, session_id=session_id)
        results.append(result)

        metrics = result.metrics
        log_level = logging.INFO if result.passed else logging.ERROR
        LOGGER.log(
            log_level,
            "[%s] %s status=%s duration=%.2fs deltas=%s lines=%s bytes=%s runtime_session=%s reasons=%s",
            result.request_id,
            "PASS" if result.passed else "FAIL",
            metrics.status_code,
            metrics.duration_seconds,
            metrics.delta_events,
            metrics.line_count,
            metrics.bytes_received,
            metrics.runtime_session_id or "-",
            "; ".join(result.reasons) if result.reasons else "-",
        )
    return results


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Automated streaming load/soak tester for the BFF/AgentCore NDJSON chat endpoint. "
            "Designed to validate long-lived streaming connectivity up to the 900s API timeout."
        )
    )
    parser.add_argument(
        "--url",
        help=(
            "Exact chat endpoint URL. If omitted, reads terraform output "
            "'agentcore_bff_api_url' (or SPA URL with --use-spa-url) and appends the default chat path."
        ),
    )
    parser.add_argument(
        "--use-spa-url",
        action="store_true",
        help=(
            "Use terraform output agentcore_bff_spa_url and default path /api/chat "
            "instead of direct API URL + /chat."
        ),
    )
    parser.add_argument("--prompt", help="Explicit prompt to send. Overrides the built-in mock-tool prompt template.")
    parser.add_argument(
        "--duration-seconds",
        type=int,
        default=900,
        help="Target runtime duration to request from the long-running mock tool (default: 900).",
    )
    parser.add_argument(
        "--heartbeat-seconds",
        type=int,
        default=15,
        help="Progress heartbeat interval referenced in the default prompt template (default: 15).",
    )
    parser.add_argument(
        "--min-stream-seconds",
        type=float,
        help="Minimum observed connection duration to treat a run as PASS (default: duration-seconds).",
    )
    parser.add_argument(
        "--socket-timeout-seconds",
        type=float,
        help="Socket timeout for connect/read operations (default: duration-seconds + 30).",
    )
    parser.add_argument(
        "--min-delta-events",
        type=int,
        default=1,
        help="Minimum number of NDJSON delta events required for PASS (default: 1).",
    )
    parser.add_argument(
        "--fail-on-error-event",
        action="store_true",
        default=False,
        help="Fail a run if any NDJSON event has type=error (default: off).",
    )
    parser.add_argument(
        "--allow-non-ndjson",
        dest="require_ndjson",
        action="store_false",
        help="Allow non-NDJSON response content-types (default requires application/x-ndjson).",
    )
    parser.set_defaults(require_ndjson=True)

    parser.add_argument(
        "--session-cookie",
        help="Value for BFF session cookie. If it does not include 'session_id=', the prefix is added automatically.",
    )
    parser.add_argument("--cookie-header", help="Full Cookie header value (overrides --session-cookie).")
    parser.add_argument("--bearer-token", help="Optional Authorization bearer token for non-cookie endpoints.")
    parser.add_argument(
        "--header",
        action="append",
        help="Additional request header in 'Name: Value' format. Can be repeated.",
    )
    parser.add_argument("--insecure", action="store_true", help="Disable TLS certificate verification (debug only).")
    parser.add_argument("--concurrency", type=int, default=1, help="Parallel worker count (default: 1).")
    parser.add_argument("--iterations", type=int, default=1, help="Requests per worker (default: 1).")
    parser.add_argument(
        "--stagger-seconds",
        type=float,
        default=0.0,
        help="Start delay multiplier between workers; worker N delays by (N-1)*stagger (default: 0).",
    )
    parser.add_argument(
        "--session-id-prefix",
        default="streaming-load-test",
        help="Prefix for generated request session IDs (default: streaming-load-test).",
    )
    parser.add_argument("--json-summary", action="store_true", help="Print final summary JSON to stdout.")
    parser.add_argument("-v", "--verbose", action="count", default=0, help="Increase log verbosity (repeatable).")
    return parser.parse_args(argv)


def validate_args(args: argparse.Namespace) -> None:
    if args.concurrency < 1:
        raise ValueError("--concurrency must be >= 1")
    if args.iterations < 1:
        raise ValueError("--iterations must be >= 1")
    if args.duration_seconds < 1:
        raise ValueError("--duration-seconds must be >= 1")
    if args.heartbeat_seconds < 1:
        raise ValueError("--heartbeat-seconds must be >= 1")
    if args.min_delta_events < 0:
        raise ValueError("--min-delta-events must be >= 0")
    if args.stagger_seconds < 0:
        raise ValueError("--stagger-seconds must be >= 0")


def configure_logging(verbosity: int) -> None:
    level = logging.WARNING
    if verbosity == 1:
        level = logging.INFO
    elif verbosity >= 2:
        level = logging.DEBUG
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)s %(message)s")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    configure_logging(args.verbose)

    try:
        validate_args(args)
        url = resolve_target_url(args.url, args.use_spa_url)
        prompt = args.prompt or build_default_prompt(args.duration_seconds, args.heartbeat_seconds)
        min_stream_seconds = (
            float(args.duration_seconds) if args.min_stream_seconds is None else float(args.min_stream_seconds)
        )
        socket_timeout_seconds = (
            float(args.duration_seconds + 30)
            if args.socket_timeout_seconds is None
            else float(args.socket_timeout_seconds)
        )

        thresholds = Thresholds(
            min_stream_seconds=min_stream_seconds,
            min_delta_events=args.min_delta_events,
            require_ndjson=args.require_ndjson,
            fail_on_error_event=args.fail_on_error_event,
        )
        config = RequestConfig(
            url=url,
            prompt=prompt,
            duration_seconds=args.duration_seconds,
            socket_timeout_seconds=socket_timeout_seconds,
            headers=build_headers(args),
            insecure=args.insecure,
            thresholds=thresholds,
        )
    except Exception as exc:
        LOGGER.error("configuration error: %s", exc)
        return 2

    total_requests = args.concurrency * args.iterations
    LOGGER.warning(
        "Starting streaming load test: url=%s concurrency=%s iterations=%s total=%s duration=%ss min_stream=%.1fs "
        "socket_timeout=%.1fs",
        config.url,
        args.concurrency,
        args.iterations,
        total_requests,
        config.duration_seconds,
        config.thresholds.min_stream_seconds,
        config.socket_timeout_seconds,
    )

    all_results: list[RunResult] = []
    with ThreadPoolExecutor(max_workers=args.concurrency, thread_name_prefix="streamload") as executor:
        futures = [
            executor.submit(
                worker_runner,
                worker_id,
                args.iterations,
                config,
                args.session_id_prefix,
                args.stagger_seconds,
            )
            for worker_id in range(1, args.concurrency + 1)
        ]
        for future in as_completed(futures):
            all_results.extend(future.result())

    all_results.sort(key=lambda r: (r.worker_id, r.iteration))
    summary = build_summary(all_results)

    passed = summary["failed"] == 0
    summary_line = (
        f"SUMMARY total={summary['total_requests']} passed={summary['passed']} failed={summary['failed']} "
        f"duration_avg={summary['duration_seconds']['avg']:.2f}s duration_max={summary['duration_seconds']['max']:.2f}s "
        f"delta_avg={summary['delta_events']['avg']:.2f}"
    )
    if passed:
        LOGGER.warning(summary_line)
    else:
        LOGGER.error(summary_line)

    if args.json_summary:
        json.dump(summary, sys.stdout, indent=2)
        sys.stdout.write("\n")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
