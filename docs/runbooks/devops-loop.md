# DevOps Loop Runbook

Checked: 2026-03-10

This runbook maps the developer harness to the repository's DevOps interaction surface so contributors do not have to reverse-engineer the full CI/CD topology before making a normal change.

## Goal

Use the smallest lane that matches the question:

- editing code locally: `validate-fast`
- starting or resuming work with prompt/yolo handoff: `worktree` or `worktree-agent-handoff`
- checking current-doc / generated-artifact drift: `validate-ci-fast`
- preparing to push a branch: `worktree-push-issue`
- approximating the broad validation lane locally: `validate-ci-full`
- releasing or promoting: follow GitHub + GitLab release flow only after merge

## Local Lanes

Fast inner loop:

```bash
make validate-fast
```

Docs / metadata / queue sanity:

```bash
make validate-ci-fast
```

Broad local validation:

```bash
make validate-ci-full
```

Push current issue branch with enforced preflight + validation:

```bash
make worktree-push-issue
```

Prompt / assistant / yolo handoff for the current or selected issue worktree:

```bash
make worktree-agent-handoff
```

## CI Fitness

Current fitness assessment:

- Local developer loop: good
  - queue -> worktree -> fast validate -> push
- Review loop: good
  - finish summary, issue evidence, and PR linkage are explicit
- Validation surface: medium complexity
  - GitHub Actions is broad but understandable
  - GitLab promotion/deploy is inherently heavier and should remain separate from normal coding flow
- Current technical drag:
  - Terraform validation still surfaces a pre-existing BFF/runtime dependency cycle
  - first-run provider bootstrap is slower than the steady-state path

## Known Current CI Debt

These are not part of the default contributor loop unless the assigned issue explicitly targets them:

- `terraform-validate`: pre-existing BFF/runtime dependency cycle
- `examples-validate`: same Terraform dependency cycle, exercised through example tfvars
- `template-test`: generated template pinned to release-tag module inputs that have drifted from the current template surface

Treat these as platform or release debt. Do not bury them inside unrelated docs/workflow PRs just to make checks green.

To keep docs/workflow/governance PRs mergeable, CI now skips these heavyweight jobs when the changed-path set does not touch the relevant Terraform/template surface.

## Cognitive Load Rules

- Do not start with the full CI surface unless you are debugging CI.
- Use `validate-fast` during implementation.
- Use `validate-ci-fast` when the change is doc/governance/workflow heavy.
- Use `worktree-push-issue` instead of manually remembering preflight + push sequencing.
- Treat GitHub Actions as the validation surface and GitLab CI as the promotion/deploy surface.

## GitHub vs GitLab

GitHub Actions:
- validation-only
- PR feedback
- broad static and offline checks

GitLab CI:
- promotion gates
- deploy / smoke-test flow
- release verification across environments

Do not mix the two mental models during ordinary development. The normal path is:
1. complete execution issue work in a worktree
2. run local validation
3. push branch / open PR
4. watch GitHub validation
5. only after merge, interact with GitLab release/promotion flow if the issue actually requires it
