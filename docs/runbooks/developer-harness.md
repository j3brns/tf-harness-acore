# Developer Harness Runbook

Checked: 2026-03-10

This runbook defines the default development loop for this repository as a harness: issue queue, linked worktree, fast local validation, push validation, and guided finish. It is intentionally narrower than the full repo policy surface.

## Goal

Optimize for this path:

```bash
make issue-queue
make worktree
make validate-fast
make validate-scope SCOPE=terraform
make validate-push
make finish-worktree-summary
make finish-worktree-close
```

## Operating Model

- One `execution` issue maps to one linked worktree, one branch, and one PR.
- `tracker` issues coordinate work and decomposition; they do not carry mixed implementation unless explicitly planning/docs only.
- The `ready` queue is the only allocation queue for active implementation work.
- Branches follow `wt/<scope>/<issue>-<slug>`.
- Worktree state progresses through `implementing`, `ready-to-push`, `pr-open`, `review`, `merged`, `cleanup-complete`.

## Inner Loop

1. Pick work from the queue:

```bash
make issue-queue
make worktree
```

2. Start every session with worktree preflight:

```bash
make preflight-session
```

3. If the change touches AWS behavior, availability, limits, IAM semantics, or AgentCore service behavior, query AWS Knowledge MCP before editing code or docs.
   Exact loop:
   - use `search_documentation` or `get_regional_availability`
   - read the returned AWS documentation page
   - record the check date in issue/PR evidence for time-sensitive facts

4. Iterate with the fast local loop:

```bash
make validate-fast
```

5. Run scope-specific checks before push:

```bash
make validate-scope SCOPE=terraform
```

Valid `SCOPE` values:
- `terraform`
- `python`
- `docs`
- `frontend`
- `all`

6. Run the full pre-push gate:

```bash
make validate-push
```

7. Inspect finish state and complete the guided finish protocol:

```bash
make finish-worktree-summary
make finish-worktree-close
```

## Queue Contract

An issue is not `ready` unless it contains:

- issue type: `execution` or `tracker`
- exactly one status label
- explicit closure condition
- touched-path expectation
- validation commands
- dependencies/blockers

Recommended labels:

- status: `triage`, `ready`, `in-progress`, `blocked`, `review`, `done`
- type: `execution`, `tracker`
- stream: `a`, `b`, `c`, `d`, `e`
- priority: `p0`, `p1`, `p2`, `p3`

## Validation Tiers

`make validate-fast`
- `make preflight-session`
- `make terraform-init-local` bootstrap into `.scratch/tf-data` and `.scratch/tf-plugin-cache` on first run
- `terraform fmt -check -recursive`
- `make terraform-validate-local`
- `make validate-region`

`make validate-scope`
- `terraform`: the fast path
- `python`: example unit tests
- `docs`: metadata and generated-client drift
- `frontend`: frontend tests
- `all`: full push gate

`make validate-push`
- preflight
- local Terraform init via scratch caches
- Terraform fmt/validate/plan
- AgentCore region validation
- policy report
- TFLint
- Checkov
- `pre-commit run --all-files`

First local bootstrap note:
- the first `make terraform-init-local` run needs network access to fetch provider packages
- after that, the scratch plugin cache is reused for local validation

## Toolchain Check

Use this when validating the local harness environment:

```bash
make toolchain-versions
```

Current repo constraints at check time:
- Terraform CLI required: `>= 1.10.0`
- AWS provider: `~> 6.33.0`

## AWS Knowledge Checkpoints

Checked 2026-03-10 using AWS Knowledge MCP:
- AgentCore regional support reference: `https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html`
- AgentCore IAM/service authorization reference: `https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html`

Inference:
- AgentCore regional coverage and IAM/resource semantics are still moving enough that AWS-specific edits should not rely on repo memory alone.
