# Development Rules for AI Coding Agents
## Bedrock AgentCore Terraform

This file is the repo source of truth for agent workflow and hard constraints. `CLAUDE.md` and `GEMINI.md` must remain byte-identical mirrors of this file.

## Temporary Prolog: v0.1.x Release Freeze

Status: active until the release-freeze exit criteria are met.

- Keep release commits limited to versioning, governance, docs-sync, and blocker fixes.
- Push `main` and release tags to both `origin` and `gitlab`.
- Validate both CI systems before calling a release finished.
- Remove this prolog in the same change that completes the freeze.

Exit criteria:
- `VERSION` matches `v0.1.x`
- `CHANGELOG.md` has the matching release entry
- `main` and the release tag exist on both remotes
- GitHub Actions and GitLab CI are green for the tagged SHA

## Rule 0: Quick Start

### Rule 0.1: Session Contract

Before editing:
1. Read `AGENTS.md` and use it as the rules source of truth.
2. Run `make preflight-session` and stop if it fails.
3. Confirm the assigned issue type and closure condition.
4. Work only in the assigned issue worktree/branch.
5. Keep the PR scoped to the issue; split if scope expands materially.
6. Use AWS Knowledge MCP first for AWS-specific questions.
7. Follow the finish protocol in Rule 12; local validation alone is not done.
8. Update required docs in the same change when behavior, workflow, or architecture changes.

### Rule 0.2: Default Harness Loop

Use this as the normal path:

```bash
make issue-queue
make worktree-next-issue OPEN_SHELL=1
make validate-fast
make validate-scope SCOPE=terraform
make worktree-push-issue
make finish-worktree-summary
```

`make worktree` remains available for the interactive menu and advanced paths.

### Rule 0.3: Rule Precedence

Apply conflicts in this order:
1. Security and safety
2. Architecture and boundary rules
3. Issue scope and allocation rules
4. Active release-freeze rules
5. Workflow convenience

If no compliant path exists, stop and report the conflict explicitly.

## Rule 1: Security Is Non-Negotiable

### Rule 1.1: IAM Resources Must Be Specific

- `Resource = "*"` is forbidden unless AWS does not support resource scoping for that action.
- Every approved wildcard must include `# AWS-REQUIRED: <reason>`.
- New wildcard exceptions require an AWS primary source and tests covering only the approved exception.

Approved wildcard exceptions:
- `logs:PutResourcePolicy`
- `sts:GetCallerIdentity`
- `ec2:CreateNetworkInterface`
- `s3:ListAllMyBuckets`

### Rule 1.2: Fail Fast

- Do not suppress provisioner errors with `|| true`, `2>/dev/null`, or equivalent masking.
- Missing input paths, failed copies, and failed CLI calls must abort with an explicit error.

### Rule 1.3: Input and Secret Hygiene

- No hardcoded ARNs, account IDs, or regions.
- Validate user inputs such as ARNs, URLs, and account IDs.
- Mark secrets `sensitive = true`.
- Use AWS-managed encryption by default unless a documented regulatory exception requires KMS.

## Rule 2: Module Architecture Is Fixed

Dependency direction:

`foundation -> tools/runtime -> governance`

Module boundaries:
- `foundation`: gateway, identity, observability
- `tools`: browser, code interpreter
- `runtime`: runtime, memory, packaging
- `governance`: policies, evaluations
- `bff`: token handler, SPA/API edge, proxy

Do not introduce circular dependencies or move components across module boundaries without an ADR-level decision.

## Rule 3: Coding Rules

### Rule 3.1: Terraform

- Prefer `for_each` with stable keys over `count`.
- Use explicit types and validation for variables.
- Use dynamic blocks only for repeatable nested blocks, never for single attributes.
- Prefer native provider resources where stable; use CLI bridges only where coverage is missing or intentionally deferred.

### Rule 3.2: Python

- Python `3.12` only.
- Format: Black + Flake8, line length `120`.
- Tests live under `examples/*/agent-code/tests/`.
- Use `logging`, not `print`.
- Unit tests must not make real network calls.

## Rule 4: Native-vs-CLI Resource Policy

This repo is no longer CLI-only. Use the current repo/provider matrix:

- Native in this repo: gateway, gateway targets, workload identity, browser, code interpreter, runtime, memory
- CLI bridge still accepted where native coverage is missing or not yet adopted: policy engine, Cedar policies, evaluators, credential providers, other gaps documented in code/comments

When changing resource control-plane strategy:
- update the migration matrix or code comments in the same change
- do not reintroduce CLI bridges where native coverage is already stable in the repo

## Rule 5: AWS Query Source of Truth

For AWS-specific questions, use AWS Knowledge MCP first.

Required flow:
1. `get_regional_availability` for region questions
2. `search_documentation` for API, CLI, limits, errors, or best practices
3. `read_documentation` for the chosen AWS doc page
4. include the exact check date for time-sensitive facts

If AWS Knowledge MCP is unavailable, say so explicitly and fall back to official AWS docs only.

## Rule 6: Versioning and Releases

- Canonical version lives in `VERSION`.
- Release tags are `vMAJOR.MINOR.PATCH`.
- Update `VERSION` and `CHANGELOG.md` together.
- Push release commits and tags to both `origin` and `gitlab`.
- Validate GitHub Actions and GitLab CI before calling a release complete.

## Rule 7: Docs, Sprawl, and Harness Workflow

### Rule 7.1: Mirrored Agent Rule Docs

- `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` must remain byte-identical.
- Edit one source and mirror it verbatim in the same change.

### Rule 7.1.2: Session Discovery Rule Promotion

- Session-discovered rules may be added only if they are durable, repo-wide, and expected to matter beyond the current issue.
- Do not promote temporary tactics, one-off debugging notes, or issue-local preferences into agent rules.
- Add promoted rules to `AGENTS.md` and mirror them to `CLAUDE.md` and `GEMINI.md` in the same change.
- If a promoted rule changes workflow or expected behavior, update the relevant docs in the same change.
- Keep promoted rules compact; prefer tightening an existing rule over adding a new sprawling section.

### Rule 7.2: Docs Sync

- Behavior, workflow, CI/CD, or architecture changes require doc updates in the same change.
- Do not defer docs to a follow-up commit.

### Rule 7.3: Scratch and New Files

- Temporary outputs and one-off investigation files belong in `.scratch/` and must not be committed.
- Reusable automation belongs in established paths such as `terraform/scripts/` or `Makefile`.
- Avoid file proliferation such as `*_v2`, `*_copy`, `*_tmp`, or `*_backup`.

### Rule 7.7: Startup Preflight Is Mandatory

- Run `make preflight-session` at session start and before commit/push.

### Rule 7.7.1: CI Failure Triage

- When validation or CI fails, classify it as:
  - regression caused by the current change
  - pre-existing debt not caused by the current change
- Do not silently broaden scope to fix unrelated debt.

### Rule 7.7.2: CI Failure Output Must Be Actionable

- Surface the exact failing command, rule, or error in logs and handoffs.
- Do not treat failing validation as opaque.

### Rule 7.8: Worktree Finish and Cleanup

Use these stage names when handing off:
- `implementing`
- `ready-to-push`
- `pr-open`
- `review`
- `merged`
- `cleanup-complete`

A worktree is not finished until the issue closure condition is met and evidence is posted.

## Rule 9: Discovery and Gateway Use

- Every agent must expose `/.well-known/agent-card.json`.
- Register agents in Cloud Map or the gateway manifest.
- Tools must be accessed through the AgentCore Gateway, not direct Lambda invocation.

## Rule 10: Identity Propagation

- No anonymous agent-to-agent calls.
- Use workload tokens.
- Preserve original Entra/OIDC user context across A2A calls.

## Rule 11: Frontend Security

- No access or refresh tokens in browser storage.
- Store tokens server-side.
- Use secure, HTTP-only, `SameSite=Strict` session cookies.

## Rule 12: Issue, Worktree, and PR Discipline

### Rule 12.1: Issue Structure

Every issue used for allocation must include:
- context
- technical detail
- implementation tasks
- acceptance criteria
- closure condition

### Rule 12.2: Roadmap Alignment

- Roadmap-planned work should map cleanly to GitHub issues.
- Use issues, not roadmap prose, as the execution surface.

### Rule 12.3: Tracker vs Execution

- `tracker`: coordination and decomposition
- `execution`: one implementable work package for one worktree/branch/PR

Implementation work belongs on execution issues unless the task is explicitly planning/docs-only.

### Rule 12.4: Branch Issue ID Must Match the Execution Issue

- Branches use the execution issue number: `wt/<scope>/<issue>-<slug>`.
- Do not use tracker issue numbers for implementation branches.

### Rule 12.5: One Agent / One Execution Issue / One Worktree

- One active execution issue per agent
- One worktree per active execution issue
- Branch naming: `wt/<scope>/<issue>-<slug>`

### Rule 12.5.1: PR Scope Guard

If work broadens materially:
- split it into another issue/PR, or
- update the issue scope explicitly before continuing

Do not sneak unrelated fixes into the same PR.

### Rule 12.6: Tracker Completion

- Tracker work is done when child execution issues are allocatable, dependencies are explicit, and blockers are recorded.

### Rule 12.7: Label Hygiene

Every open issue must have:
- exactly one type label: `tracker` or `execution`
- exactly one status label: `triage`, `ready`, `in-progress`, `blocked`, `review`, or `done`

Allocatable `ready` issues must also have:
- explicit dependencies/blockers
- actionable acceptance criteria
- a closure condition
- scope suitable for one worktree

### Rule 12.8: Execution Finish Protocol

For execution issues:
1. `make preflight-session`
2. run issue-appropriate validation
3. commit focused changes with the issue number
4. push the worktree branch
5. open or update the PR to `main`
6. post an issue closeout comment with summary, validation, PR, commit SHA, and CI evidence
7. move the issue to `review` or `done`
8. close only after merge unless the workflow explicitly auto-closes on PR creation

### Rule 12.8.1: One Execution PR Must Close One Execution Issue

Execution PRs must include `Closes #<issue>` in the PR body.

### Rule 12.8.2: Review-Stage Handoff

Any pause at `pr-open` or `review` must include:
- finish stage
- PR link
- issue number and label state
- completed steps
- current blocker, if any
- exact next command(s)

### Rule 12.9: Tracker Finish Protocol

- Tracker issues finish when work is fully allocatable or coordinated.

### Rule 12.10: Definition of Done Must Be Explicit

- Every issue needs required validation, expected outcomes, required docs updates, and a closure condition.

### Rule 12.11: Label Hygiene for Queueing

- The `ready` queue is only for allocatable issues with explicit scope and closure conditions.

## Rule 13: Repo Layout

- Terraform core stays in `terraform/`
- examples stay in `examples/`
- docs stay at repo root and `docs/`

If files move, update references in docs, scripts, tests, and helper commands in the same change.

## Decision Framework

| Question | Default |
| --- | --- |
| Native or CLI? | Native when stable in this repo; CLI only for documented gaps |
| Which module? | Follow the fixed module boundaries in Rule 2 |
| Dynamic block? | Only for repeatable blocks |
| Encryption? | AWS-managed by default |
| Hardcoded ARNs/regions? | Never |
| Worktree flow? | `issue-queue -> worktree-next-issue -> validate-fast -> worktree-push-issue` |

## Before Commit

Default:

```bash
make preflight-session
make validate-fast
make validate-push
```

Use narrower `make validate-scope` paths only when the issue scope justifies it and the issue evidence records what was run.

## Rule 14: Multi-Tenant Isolation

- Never trust `tenant_id` or `session_id` from the request body without verifying against authenticated context.
- Partition S3 and DynamoDB state by `app_id` and `tenant_id`.
- Enforce ABAC conditions that bind principal tenant/app identity to resource tenant/app identity.
- Keep the North-South identity join intact across the system.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **terraform** (1327 symbols, 2849 relationships, 93 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/terraform/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/terraform/context` | Codebase overview, check index freshness |
| `gitnexus://repo/terraform/clusters` | All functional areas |
| `gitnexus://repo/terraform/processes` | All execution flows |
| `gitnexus://repo/terraform/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## Keeping the Index Fresh

After committing code changes, the GitNexus index becomes stale. Re-run analyze to update it:

```bash
npx gitnexus analyze
```

If the index previously included embeddings, preserve them by adding `--embeddings`:

```bash
npx gitnexus analyze --embeddings
```

To check whether embeddings exist, inspect `.gitnexus/meta.json` — the `stats.embeddings` field shows the count (0 means no embeddings). **Running analyze without `--embeddings` will delete any previously generated embeddings.**

> Claude Code users: A PostToolUse hook handles this automatically after `git commit` and `git merge`.

## CLI

- Re-index: `npx gitnexus analyze`
- Check freshness: `npx gitnexus status`
- Generate docs: `npx gitnexus wiki`

<!-- gitnexus:end -->
