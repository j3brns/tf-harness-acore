from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest
import io
from contextlib import redirect_stdout


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "report_sdk_drift.py"
    spec = importlib.util.spec_from_file_location("report_sdk_drift", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")


class ReportSdkDriftTests(unittest.TestCase):
    def test_extract_versions_from_toml(self):
        toml_data = {
            "project": {
                "dependencies": [
                    "bedrock-agentcore>=1.0.7",
                    "strands-agents[otel]>=1.18.0",
                ],
                "optional-dependencies": {
                    "extra": ["linkup-sdk==0.9.0"]
                }
            }
        }
        versions = mod.extract_versions_from_toml(toml_data)
        self.assertEqual(versions.get("bedrock-agentcore"), ">=1.0.7")
        self.assertEqual(versions.get("strands-agents"), ">=1.18.0")
        self.assertEqual(versions.get("linkup-sdk"), "==0.9.0")

    def test_extract_versions_from_jinja(self):
        jinja_content = """
        dependencies = [
            "bedrock-agentcore>=1.0.7",
            "strands-agents>=1.18.0",
        ]
        """
        versions = mod.extract_versions_from_jinja(jinja_content)
        self.assertEqual(versions.get("bedrock-agentcore"), ">=1.0.7")
        self.assertEqual(versions.get("strands-agents"), ">=1.18.0")

    def test_drift_detection_logic(self):
        # We'll mock the main logic by patching repo_root and using a controlled set of files
        # But for unit testing the drift detection, we can just test the output generation if we refactor main slightly.
        # Since main() is already written, let's test it by creating a temporary repo structure.
        
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            
            # Create a consistent scenario
            _write(root / "examples" / "ex1" / "pyproject.toml", """
                [project]
                dependencies = ["strands-agents>=1.18.0"]
            """)
            _write(root / "examples" / "ex2" / "pyproject.toml", """
                [project]
                dependencies = ["strands-agents>=1.18.0"]
            """)
            
            # Monkeypatch repo_root in the module
            original_repo_root = mod.repo_root
            mod.repo_root = lambda: root
            
            try:
                f = io.StringIO()
                with redirect_stdout(f):
                    # Should return 0 (no drift)
                    exit_code = mod.main([])
                
                output = f.getvalue()
                self.assertEqual(exit_code, 0)
                self.assertIn("✅ CONSISTENT", output)
                self.assertIn("strands-agents", output)
                
                # Now introduce drift
                _write(root / "examples" / "ex2" / "pyproject.toml", """
                    [project]
                    dependencies = ["strands-agents>=1.19.0"]
                """)
                
                f = io.StringIO()
                with redirect_stdout(f):
                    # Should return 1 (drift found)
                    exit_code = mod.main([])
                
                output = f.getvalue()
                self.assertEqual(exit_code, 1)
                self.assertIn("⚠️ DRIFTED", output)
                self.assertIn("strands-agents", output)
                self.assertIn(">=1.18.0", output)
                self.assertIn(">=1.19.0", output)
                
            finally:
                mod.repo_root = original_repo_root

if __name__ == "__main__":
    unittest.main()
