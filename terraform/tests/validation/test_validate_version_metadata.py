from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "validate_version_metadata.py"
    spec = importlib.util.spec_from_file_location("validate_version_metadata", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")


def _seed_repo(
    root: Path,
    *,
    version: str = "0.1.1",
    changelog_release: str = "0.1.1",
    arch_version: str = "0.1.1",
) -> None:
    major, minor, _patch = version.split(".")
    release_line = f"{major}.{minor}.x"

    _write(root / "VERSION", f"{version}\n")
    _write(
        root / "CHANGELOG.md",
        f"""
        # Changelog

        ## [Unreleased]

        ## [{changelog_release}] - 2026-02-25
        """,
    )
    _write(
        root / "README.md",
        f"""
        - Canonical repository version is stored in `VERSION` (current line: `{release_line}`).
        """,
    )
    _write(
        root / "DEVELOPER_GUIDE.md",
        f"""
        - Current release line is `{release_line}`.
        """,
    )
    _write(
        root / "docs" / "architecture.md",
        f"""
        ## Document Status

        | Aspect | Status |
        |--------|--------|
        | **Code Version** | v{arch_version} (North-South Join) |
        """,
    )


class ValidateVersionMetadataTests(unittest.TestCase):
    def test_validate_repo_passes_when_consistent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)
            self.assertEqual(mod.validate_repo(root), [])

    def test_detects_architecture_code_version_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root, arch_version="1.1.0")
            errors = mod.validate_repo(root)
            self.assertTrue(any("docs/architecture.md: Code Version" in err for err in errors), errors)

    def test_detects_latest_changelog_release_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root, changelog_release="0.1.0")
            errors = mod.validate_repo(root)
            self.assertTrue(any("CHANGELOG.md: latest released heading" in err for err in errors), errors)

    def test_detects_readme_release_line_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _seed_repo(root)
            (root / "README.md").write_text(
                "- Canonical repository version is stored in `VERSION` (current line: `0.2.x`).\n",
                encoding="utf-8",
            )
            errors = mod.validate_repo(root)
            self.assertTrue(any("README.md: release line" in err for err in errors), errors)


if __name__ == "__main__":
    unittest.main()
