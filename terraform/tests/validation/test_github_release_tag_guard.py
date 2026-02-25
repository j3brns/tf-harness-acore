from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
GITHUB_CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"


def test_release_tag_guard_enforces_strict_release_tag_format_with_checkpoint_guidance():
    content = GITHUB_CI_WORKFLOW_PATH.read_text(encoding="utf-8")

    assert "release-tag-guard:" in content
    assert "refs/tags/v" in content
    assert "grep -Eq '^v[0-9]+\\.[0-9]+\\.[0-9]+$'" in content
    assert "Release tags must match vMAJOR.MINOR.PATCH" in content
    assert "checkpoint/<label>" in content
