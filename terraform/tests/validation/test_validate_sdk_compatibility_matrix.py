from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "validate_sdk_compatibility_matrix.py"
    spec = importlib.util.spec_from_file_location("validate_sdk_compatibility_matrix", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")


def _seed_example_pyproject(
    root: Path,
    rel_path: Path,
    *,
    deps: list[str],
    dev_deps: list[str] | None = None,
) -> None:
    dev_deps = dev_deps or []
    dev_lines = "\n".join(f'    "{dep}",' for dep in dev_deps) or "    # none"
    dep_lines = "\n".join(f'    "{dep}",' for dep in deps)
    _write(
        root / rel_path / "pyproject.toml",
        f"""
        [project]
        name = "{rel_path.parts[1]}"
        version = "0.1.0"
        requires-python = ">=3.12"
        dependencies = [
        {dep_lines}
        ]

        [project.optional-dependencies]
        dev = [
        {dev_lines}
        ]
        """,
    )


class ValidateSdkCompatibilityMatrixTests(unittest.TestCase):
    def test_repo_floors_are_derived_from_maximum_declared_minimums(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Seed all configured examples so the derivation path remains realistic.
            for example in mod.EXAMPLE_CHECKS:
                _seed_example_pyproject(
                    root,
                    example.path,
                    deps=[
                        "bedrock-agentcore>=1.0.7",
                        "strands-agents>=1.18.0",
                    ],
                    dev_deps=[],
                )

            # Override a couple of examples to force max-floor selection.
            _seed_example_pyproject(
                root,
                Path("examples/3-deepresearch/agent-code"),
                deps=[
                    "bedrock-agentcore>=1.0.9",
                    "strands-agents>=1.20.0",
                    "strands-agents-tools>=0.3.0",
                    "strands-deep-agents>=0.2.0",
                ],
                dev_deps=["bedrock-agentcore-starter-toolkit>=0.1.40"],
            )
            _seed_example_pyproject(
                root,
                Path("examples/5-integrated/agent-code"),
                deps=[
                    "bedrock-agentcore>=1.0.8",
                    "strands-agents>=1.19.0",
                ],
                dev_deps=[],
            )

            floors = mod.derive_repo_floor_sdk_pins(root)
            self.assertEqual(
                floors,
                {
                    "bedrock-agentcore": "1.0.9",
                    "bedrock-agentcore-starter-toolkit": "0.1.40",
                    "strands-agents": "1.20.0",
                    "strands-agents-tools": "0.3.0",
                    "strands-deep-agents": "0.2.0",
                },
            )

    def test_write_constraints_file_skips_latest_compatible_lane(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            self.assertIsNone(mod.write_constraints_file("latest-compatible", workspace, root=Path(tmp)))

    def test_write_constraints_file_emits_curated_pins(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            constraints = mod.write_constraints_file("curated-stable", workspace)
            assert constraints is not None
            text = constraints.read_text(encoding="utf-8")
            self.assertIn("bedrock-agentcore==1.0.7", text)
            self.assertIn("strands-agents==1.18.0", text)
            self.assertIn("moto==5.0.28", text)

    def test_select_lanes_deduplicates_and_validates(self):
        lanes = mod._select_lanes(["repo-floors", "repo-floors", "curated-stable"])
        self.assertEqual(lanes, ["repo-floors", "curated-stable"])
        with self.assertRaises(mod.MatrixValidationError):
            mod._select_lanes(["not-a-lane"])

    def test_select_examples_deduplicates_and_validates(self):
        examples = mod._select_examples(["1-hello-world", "1-hello-world", "5-integrated"])
        self.assertEqual([example.name for example in examples], ["1-hello-world", "5-integrated"])
        with self.assertRaises(mod.MatrixValidationError):
            mod._select_examples(["bad-example"])


if __name__ == "__main__":
    unittest.main()
