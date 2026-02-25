#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

SEMVER_RE = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")
CHANGELOG_RELEASE_RE = re.compile(r"^## \[(?P<version>[^\]]+)\](?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$", re.MULTILINE)
README_RELEASE_LINE_RE = re.compile(r"(\(current line: `)(?P<line>\d+\.\d+\.x)(`\)\.)")
DEV_GUIDE_RELEASE_LINE_RE = re.compile(r"(Current release line is `)(?P<line>\d+\.\d+\.x)(`\.)")
ARCH_CODE_VERSION_RE = re.compile(
    r"^(\|\s*\*\*Code Version\*\*\s*\|\s*v)(?P<version>\d+\.\d+\.\d+)(?P<suffix>[^|]*)(\|\s*)$",
    re.MULTILINE,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate consistency between VERSION, CHANGELOG.md, and documented version metadata."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="Repository root path (defaults to repo root inferred from this script location).",
    )
    parser.add_argument("--quiet-success", action="store_true", help="Suppress PASS output.")
    return parser.parse_args(argv)


def _read_text(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"Required file not found: {path}")
    return path.read_text(encoding="utf-8")


def _parse_version(version_text: str) -> tuple[str, str]:
    version = version_text.strip()
    match = SEMVER_RE.fullmatch(version)
    if not match:
        raise ValueError(f"VERSION must be SemVer (MAJOR.MINOR.PATCH); found '{version}'")
    release_line = f"{match.group('major')}.{match.group('minor')}.x"
    return version, release_line


def _first_released_changelog_version(changelog_text: str) -> str | None:
    for match in CHANGELOG_RELEASE_RE.finditer(changelog_text):
        version = match.group("version").strip()
        if version.lower() == "unreleased":
            continue
        return version
    return None


def _check_release_line(text: str, pattern: re.Pattern[str], expected_release_line: str, label: str) -> list[str]:
    match = pattern.search(text)
    if not match:
        return [f"{label}: expected release-line metadata field not found"]
    actual = match.group("line")
    if actual != expected_release_line:
        return [f"{label}: release line '{actual}' does not match VERSION-derived line '{expected_release_line}'"]
    return []


def _check_architecture_code_version(text: str, expected_version: str) -> list[str]:
    match = ARCH_CODE_VERSION_RE.search(text)
    if not match:
        return ["docs/architecture.md: '**Code Version**' row not found in Document Status table"]
    actual = match.group("version")
    if actual != expected_version:
        return [
            "docs/architecture.md: Code Version "
            f"'v{actual}' does not match VERSION 'v{expected_version}' (update the Document Status table)"
        ]
    return []


def validate_repo(root: Path) -> list[str]:
    errors: list[str] = []
    version_path = root / "VERSION"
    changelog_path = root / "CHANGELOG.md"
    readme_path = root / "README.md"
    developer_guide_path = root / "DEVELOPER_GUIDE.md"
    architecture_path = root / "docs" / "architecture.md"

    try:
        version, release_line = _parse_version(_read_text(version_path))
    except (FileNotFoundError, ValueError) as exc:
        return [str(exc)]

    try:
        changelog_text = _read_text(changelog_path)
        latest_release = _first_released_changelog_version(changelog_text)
        if latest_release is None:
            errors.append("CHANGELOG.md: no released version heading found (expected '## [<version>] - YYYY-MM-DD')")
        elif latest_release != version:
            errors.append(
                "CHANGELOG.md: latest released heading "
                f"'[{latest_release}]' does not match VERSION '[{version}]'"
            )
    except FileNotFoundError as exc:
        errors.append(str(exc))

    for path, pattern, label in (
        (readme_path, README_RELEASE_LINE_RE, "README.md"),
        (developer_guide_path, DEV_GUIDE_RELEASE_LINE_RE, "DEVELOPER_GUIDE.md"),
    ):
        try:
            errors.extend(_check_release_line(_read_text(path), pattern, release_line, label))
        except FileNotFoundError as exc:
            errors.append(str(exc))

    try:
        errors.extend(_check_architecture_code_version(_read_text(architecture_path), version))
    except FileNotFoundError as exc:
        errors.append(str(exc))

    return errors


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = args.root.resolve()
    errors = validate_repo(root)
    if errors:
        print("ERROR: Version/changelog/docs metadata consistency check failed.")
        print(f"Repository root: {root}")
        for error in errors:
            print(f"  - {error}")
        print("Expected invariants:")
        print("  - VERSION is SemVer (MAJOR.MINOR.PATCH)")
        print("  - CHANGELOG.md latest released heading matches VERSION")
        print("  - README.md and DEVELOPER_GUIDE.md release-line metadata matches VERSION major.minor.x")
        print("  - docs/architecture.md Document Status Code Version matches v<VERSION>")
        return 1

    if not args.quiet_success:
        print("PASS: Version/changelog/docs metadata consistency check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
