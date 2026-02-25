#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRATCH_ROOT = REPO_ROOT / ".scratch" / "sdk-compat-matrix"

TRACKED_SDK_PACKAGES = (
    "bedrock-agentcore",
    "bedrock-agentcore-starter-toolkit",
    "strands-agents",
    "strands-agents-tools",
    "strands-deep-agents",
)

# Curated lane is explicit/repeatable for CI regression triage. Versions are intentionally
# conservative and should be updated when the repo floors move or maintainers re-baseline.
CURATED_STABLE_PINS = {
    "bedrock-agentcore": "1.0.7",
    "bedrock-agentcore-starter-toolkit": "0.1.34",
    "strands-agents": "1.18.0",
    "strands-agents-tools": "0.2.16",
    "strands-deep-agents": "0.1.1",
    "boto3": "1.40.52",
    "numpy": "1.26.4",
    "pandas": "2.2.2",
    "requests": "2.32.3",
    "pytest": "8.3.4",
    "pytest-asyncio": "0.24.0",
    "pytest-cov": "5.0.0",
    "pytest-mock": "3.14.0",
    "moto": "5.0.28",
    "linkup-sdk": "0.9.0",
}

REQ_LOWER_BOUND_RE = re.compile(
    r"^\s*(?P<name>[A-Za-z0-9_.-]+)(?:\[[^\]]+\])?\s*>=\s*(?P<version>[A-Za-z0-9_.+-]+)\s*$"
)


@dataclass(frozen=True)
class ExampleCheck:
    name: str
    path: Path
    smoke_kind: str
    smoke_target: str
    install_dev: bool = True


@dataclass(frozen=True)
class LaneSpec:
    name: str
    description: str


EXAMPLE_CHECKS = (
    ExampleCheck(
        name="1-hello-world",
        path=Path("examples/1-hello-world/agent-code"),
        smoke_kind="pytest",
        smoke_target="tests/test_handler.py::TestHandler::test_handler_success_with_buckets",
    ),
    ExampleCheck(
        name="2-gateway-tool",
        path=Path("examples/2-gateway-tool/agent-code"),
        smoke_kind="pytest",
        smoke_target="tests/test_analysis.py::TestHandler::test_handler_success",
    ),
    ExampleCheck(
        name="3-deepresearch",
        path=Path("examples/3-deepresearch/agent-code"),
        smoke_kind="pytest",
        smoke_target="tests/integration/test_agent_creation.py::TestAgentCreation::test_detects_strands_graph",
    ),
    ExampleCheck(
        name="4-research",
        path=Path("examples/4-research/agent-code"),
        smoke_kind="pytest",
        smoke_target="tests/test_research_agent.py::TestHandler::test_handler_success",
    ),
    ExampleCheck(
        name="5-integrated",
        path=Path("examples/5-integrated/agent-code"),
        smoke_kind="python",
        smoke_target=(
            "from runtime import handler; "
            "result = handler({'action': 'analyze'}, None); "
            "assert result['status'] == 'success', result"
        ),
    ),
)

LANE_SPECS = (
    LaneSpec(
        name="repo-floors",
        description=(
            "Exact pins derived from repo-declared minimum Strands/AgentCore SDK floors "
            "across example pyproject files."
        ),
    ),
    LaneSpec(
        name="curated-stable",
        description="Repo-maintained explicit pin set for reproducible CI triage and baseline coverage.",
    ),
    LaneSpec(
        name="latest-compatible",
        description="No constraints; resolve the newest versions compatible with each example's declared ranges.",
    ),
)


class MatrixValidationError(RuntimeError):
    pass


def _normalize_name(name: str) -> str:
    return name.strip().lower().replace("_", "-")


def _version_key(version: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in version.split("."))
    except ValueError as exc:
        raise ValueError(f"Unsupported non-numeric version '{version}' for floor comparison") from exc


def _read_pyproject(root: Path, rel_path: Path) -> dict:
    path = root / rel_path / "pyproject.toml"
    if not path.exists():
        raise FileNotFoundError(f"Missing pyproject.toml for example: {path}")
    with path.open("rb") as fh:
        return tomllib.load(fh)


def _iter_dependency_strings(pyproject: dict) -> list[str]:
    project = pyproject.get("project", {})
    values: list[str] = []
    values.extend(project.get("dependencies", []) or [])
    optional = project.get("optional-dependencies", {}) or {}
    for extra_name in ("dev",):
        values.extend(optional.get(extra_name, []) or [])
    return values


def derive_repo_floor_sdk_pins(root: Path = REPO_ROOT) -> dict[str, str]:
    floors: dict[str, str] = {}
    tracked = {_normalize_name(pkg) for pkg in TRACKED_SDK_PACKAGES}
    for example in EXAMPLE_CHECKS:
        pyproject = _read_pyproject(root, example.path)
        for requirement in _iter_dependency_strings(pyproject):
            match = REQ_LOWER_BOUND_RE.match(requirement)
            if not match:
                continue
            name = _normalize_name(match.group("name"))
            if name not in tracked:
                continue
            version = match.group("version")
            if name not in floors or _version_key(version) > _version_key(floors[name]):
                floors[name] = version

    missing = sorted(tracked - floors.keys())
    if missing:
        raise MatrixValidationError(
            "Unable to derive repo-floors lane; missing lower-bound declarations for tracked packages: "
            + ", ".join(missing)
        )
    return dict(sorted(floors.items()))


def get_lane_names() -> list[str]:
    return [lane.name for lane in LANE_SPECS]


def _get_example_by_name(name: str) -> ExampleCheck:
    for example in EXAMPLE_CHECKS:
        if example.name == name:
            return example
    valid = ", ".join(e.name for e in EXAMPLE_CHECKS)
    raise MatrixValidationError(f"Unknown example '{name}'. Valid examples: {valid}")


def _get_lane_spec(name: str) -> LaneSpec:
    for lane in LANE_SPECS:
        if lane.name == name:
            return lane
    valid = ", ".join(get_lane_names())
    raise MatrixValidationError(f"Unknown lane '{name}'. Valid lanes: {valid}")


def get_lane_pins(lane_name: str, root: Path = REPO_ROOT) -> dict[str, str]:
    if lane_name == "repo-floors":
        return derive_repo_floor_sdk_pins(root)
    if lane_name == "curated-stable":
        return dict(sorted(CURATED_STABLE_PINS.items()))
    if lane_name == "latest-compatible":
        return {}
    _get_lane_spec(lane_name)
    raise AssertionError("unreachable")


def _format_constraints_lines(pins: dict[str, str]) -> list[str]:
    return [f"{name}=={pins[name]}" for name in sorted(pins)]


def write_constraints_file(lane_name: str, workspace: Path, root: Path = REPO_ROOT) -> Path | None:
    pins = get_lane_pins(lane_name, root=root)
    if not pins:
        return None
    constraints_path = workspace / f"{lane_name}.constraints.txt"
    lines = _format_constraints_lines(pins)
    constraints_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return constraints_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run fast SDK compatibility smoke checks for example agents across version lanes "
            "(Strands + Bedrock AgentCore focus)."
        )
    )
    parser.add_argument(
        "--lane",
        dest="lanes",
        action="append",
        help=f"Lane to run (repeatable). Valid: {', '.join(get_lane_names())}. Defaults to all lanes.",
    )
    parser.add_argument(
        "--example",
        dest="examples",
        action="append",
        help="Example to run (repeatable). Defaults to all configured examples.",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        default=SCRATCH_ROOT,
        help="Scratch working directory for venvs/constraints (default: .scratch/sdk-compat-matrix).",
    )
    parser.add_argument(
        "--list-lanes",
        action="store_true",
        help="Print lane names, descriptions, and current pin sets (if any), then exit.",
    )
    parser.add_argument(
        "--reuse-venv",
        action="store_true",
        help="Reuse per-lane virtualenvs if present (local speed optimization). CI should not use this.",
    )
    parser.add_argument(
        "--skip-pip-upgrade",
        action="store_true",
        help="Skip upgrading pip/setuptools/wheel in each lane venv.",
    )
    return parser.parse_args(argv)


def _select_lanes(requested: list[str] | None) -> list[str]:
    if not requested:
        return get_lane_names()
    seen: list[str] = []
    for lane in requested:
        _get_lane_spec(lane)
        if lane not in seen:
            seen.append(lane)
    return seen


def _select_examples(requested: list[str] | None) -> list[ExampleCheck]:
    if not requested:
        return list(EXAMPLE_CHECKS)
    selected: list[ExampleCheck] = []
    seen: set[str] = set()
    for name in requested:
        example = _get_example_by_name(name)
        if example.name in seen:
            continue
        seen.add(example.name)
        selected.append(example)
    return selected


def _print_lanes(root: Path) -> None:
    print("SDK compatibility matrix lanes:")
    for lane in LANE_SPECS:
        print(f"- {lane.name}: {lane.description}")
        pins = get_lane_pins(lane.name, root=root)
        if not pins:
            print("  pins: none (resolver latest-compatible)")
            continue
        for line in _format_constraints_lines(pins):
            print(f"  {line}")


def _run(
    cmd: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    label: str,
) -> None:
    print(f"[{label}] RUN: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, env=env, check=True)
    except subprocess.CalledProcessError as exc:
        raise MatrixValidationError(f"{label}: command failed with exit code {exc.returncode}") from exc


def _venv_python(venv_dir: Path) -> Path:
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def _prepare_venv(
    *,
    lane_name: str,
    lane_workspace: Path,
    reuse_venv: bool,
    skip_pip_upgrade: bool,
) -> Path:
    venv_dir = lane_workspace / "venv"
    try:
        import ensurepip  # noqa: F401
    except ImportError as exc:
        raise MatrixValidationError(
            f"lane={lane_name}: Python venv support is unavailable (ensurepip missing). "
            "Install the OS venv package (for example `python3.12-venv` on Debian/Ubuntu) and retry."
        ) from exc
    if venv_dir.exists() and not reuse_venv:
        shutil.rmtree(venv_dir)
    if not venv_dir.exists():
        _run([sys.executable, "-m", "venv", str(venv_dir)], cwd=REPO_ROOT, label=f"lane={lane_name}")
    py = _venv_python(venv_dir)
    if not py.exists():
        raise MatrixValidationError(f"lane={lane_name}: virtualenv python not found at {py}")
    if not skip_pip_upgrade:
        _run(
            [str(py), "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            cwd=REPO_ROOT,
            label=f"lane={lane_name}",
        )
    return py


def _install_example(
    *,
    py: Path,
    example: ExampleCheck,
    constraints_path: Path | None,
    lane_name: str,
    root: Path,
) -> None:
    cmd = [str(py), "-m", "pip", "install"]
    if constraints_path is not None:
        cmd.extend(["-c", str(constraints_path)])
    cmd.extend(["-e", ".[dev]" if example.install_dev else "."])
    _run(cmd, cwd=root / example.path, label=f"lane={lane_name} example={example.name} install")


def _run_smoke(*, py: Path, example: ExampleCheck, lane_name: str, root: Path) -> None:
    if example.smoke_kind == "pytest":
        cmd = [str(py), "-m", "pytest", "-v", "--tb=short", example.smoke_target]
    elif example.smoke_kind == "python":
        cmd = [str(py), "-c", example.smoke_target]
    else:
        raise MatrixValidationError(f"Unsupported smoke kind '{example.smoke_kind}' for {example.name}")
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    _run(cmd, cwd=root / example.path, env=env, label=f"lane={lane_name} example={example.name} smoke")


def run_matrix(
    *,
    lanes: list[str],
    examples: list[ExampleCheck],
    work_dir: Path,
    reuse_venv: bool,
    skip_pip_upgrade: bool,
    root: Path = REPO_ROOT,
) -> int:
    work_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []

    print("SDK compatibility matrix configuration:")
    print(f"- repo root: {root}")
    print(f"- work dir: {work_dir}")
    print(f"- lanes: {', '.join(lanes)}")
    print(f"- examples: {', '.join(example.name for example in examples)}")

    for lane_name in lanes:
        lane_spec = _get_lane_spec(lane_name)
        lane_workspace = work_dir / lane_name
        lane_workspace.mkdir(parents=True, exist_ok=True)
        constraints_path = write_constraints_file(lane_name, lane_workspace, root=root)
        pins = get_lane_pins(lane_name, root=root)

        print("")
        print(f"=== LANE {lane_name} ===")
        print(f"Description: {lane_spec.description}")
        if pins:
            print("Pinned packages:")
            for line in _format_constraints_lines(pins):
                print(f"  - {line}")
        else:
            print("Pinned packages: none (resolver latest-compatible)")

        try:
            py = _prepare_venv(
                lane_name=lane_name,
                lane_workspace=lane_workspace,
                reuse_venv=reuse_venv,
                skip_pip_upgrade=skip_pip_upgrade,
            )
            for example in examples:
                print(f"\n--- [{lane_name}] Example {example.name} ---")
                _install_example(
                    py=py,
                    example=example,
                    constraints_path=constraints_path,
                    lane_name=lane_name,
                    root=root,
                )
                _run_smoke(py=py, example=example, lane_name=lane_name, root=root)
        except MatrixValidationError as exc:
            failures.append(str(exc))
            print(f"ERROR: {exc}")

    print("")
    if failures:
        print("SDK compatibility matrix FAILED.")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("SDK compatibility matrix PASSED.")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    lanes = _select_lanes(args.lanes)
    examples = _select_examples(args.examples)
    root = REPO_ROOT

    if args.list_lanes:
        _print_lanes(root)
        return 0

    try:
        return run_matrix(
            lanes=lanes,
            examples=examples,
            work_dir=args.work_dir,
            reuse_venv=args.reuse_venv,
            skip_pip_upgrade=args.skip_pip_upgrade,
            root=root,
        )
    except MatrixValidationError as exc:
        print(f"ERROR: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
