from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
GITLAB_CI_PATH = REPO_ROOT / ".gitlab-ci.yml"


def _gitlab_ci_text() -> str:
    return GITLAB_CI_PATH.read_text(encoding="utf-8")


def test_promotion_gate_jobs_emit_sha_evidence_artifacts():
    content = _gitlab_ci_text()

    required_artifacts = [
        "promote-dev-evidence-${CI_COMMIT_SHA}.json",
        "promote-test-evidence-${CI_COMMIT_SHA}.json",
        "gate-prod-from-test-evidence-${CI_COMMIT_SHA}.json",
    ]

    for marker in required_artifacts:
        assert marker in content, f"Missing promotion gate evidence artifact marker: {marker}"

    assert "PROMOTE_DEV_EVIDENCE_FILE=" in content
    assert "PROMOTE_TEST_EVIDENCE_FILE=" in content


def test_promote_test_requires_promote_dev_gate():
    content = _gitlab_ci_text()

    assert 'select(.name=="promote:dev" and .status=="success")' in content
    assert "ERROR: promote:dev is not successful in this pipeline. Promote dev first." in content


def test_prod_gate_requires_gate_evidence_and_test_success():
    content = _gitlab_ci_text()

    assert 'job_success_with_artifact "promote:dev"' in content
    assert 'job_success_with_artifact "promote:test"' in content
    assert "artifacts_file.filename" in content
    assert 'job_success "deploy:test"' in content
    assert 'job_success "smoke-test:test"' in content
    assert "promote:dev/promote:test evidence plus deploy:test + smoke-test:test" in content


def test_prod_jobs_are_release_tag_only_not_any_tag():
    content = _gitlab_ci_text()

    release_tag_rule = "CI_COMMIT_TAG =~ /^v[0-9]+\\.[0-9]+\\.[0-9]+$/"
    assert content.count(release_tag_rule) >= 4
    assert content.count("- when: never") >= 4
    assert "Prod promotion gate only applies to release tags (vMAJOR.MINOR.PATCH)." in content
