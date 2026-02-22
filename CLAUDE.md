# Development Rules & Principles for AI Coding Agents
## Bedrock AgentCore Terraform

> **Critical**: This is NOT a typical Terraform project. Read ALL rules before making ANY changes.

---

## TEMPORARY PROLOG: Migration Plan (v0.1.x Freeze)

**Status**: Temporary. Applies until the exit criteria below are met.

### Purpose
- Freeze a clean SemVer baseline (`0.1.x`) without carrying repository sprawl into release history.
- Align GitHub (`origin`) and GitLab (`gitlab`) release behavior.

### Execution Order (Mandatory)
1. Snapshot current mixed work to a non-release WIP branch; do not delete files.
2. Build a clean release commit containing only versioning/governance/docs-sync changes.
3. Run local gates before push: fmt, validate, tflint, checkov, pre-commit.
4. Push `main` to both remotes: `origin` and `gitlab`.
5. Create release tag `v0.1.x`, then push the tag to both remotes.
6. Verify both CI systems:
   - GitHub Actions: validation green on commit/tag.
   - GitLab CI: promotion/deployment gates green or approved.
7. Record release evidence (tag, SHAs, CI URLs) in release notes/changelog context.
8. Move remaining sprawl cleanup to follow-up scoped commits (no mixed release commits).

### Temporary Constraints
- No net-new feature work is allowed in the release freeze commit unless it is a release blocker fix.
- No script/file proliferation during migration; one-off artifacts remain in `.scratch/` and uncommitted.
- `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` must stay byte-identical.

### Exit Criteria (Remove This Prolog After Completion)
- `VERSION` matches release tag `v0.1.x`.
- `CHANGELOG.md` contains the matching release entry.
- `main` and release tag are present on both remotes (`origin`, `gitlab`).
- GitHub Actions and GitLab CI are green for the tagged release SHA.

---

## RULE 0: Quick Start (Hard Stops)

### Non-Negotiables
- **No IAM wildcard resources** (except documented AWS-required exceptions).
- **No error suppression** in provisioners (Fail Fast).
- **No hardcoded ARNs, regions, or account IDs**.
- **Validate all user inputs** (ARNs, URLs, account IDs).
- **Use AWS-managed encryption** (SSE-S3) unless regulatory exception.
- **Use dynamic blocks ONLY for repeatable blocks**, never for single attributes.

### Key References
- **Architecture**: `docs/architecture.md`
- **ADRs**: `docs/adr/` (Review 0009, 0010, 0011)
- **Human Guide**: `DEVELOPER_GUIDE.md`

---

## RULE 1: Security is NON-NEGOTIABLE

### Critical Security Findings (Remediated)

**DEPLOYMENT BLOCKERS remediated**:
1. IAM wildcard resources (3 instances) - REMEDIATED: Scoped to specific ARNs or documented as AWS-required exceptions.
2. Dynamic block syntax errors - FIXED: Replaced with direct attributes.
3. Error suppression masking failures - FIXED: Implemented fail-fast error handling in all provisioners.
4. Placeholder ARN validation missing - FIXED: Added variable validation.
5. Dependency package limits - FIXED: Removed arbitrary limits.

### Security Rules - NEVER Violate These

#### Rule 1.1: IAM Resources MUST Be Specific
```hcl
# FORBIDDEN:
Resource = "*"

# REQUIRED:
Resource = [
  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
]
Condition = {
  StringEquals = {
    "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  }
}
```

**Known Exceptions (AWS-Required Wildcards)**:
Certain actions do NOT support resource-level scoping and MUST use `Resource = "*"`. These are accommodated in tests:
- `logs:PutResourcePolicy`: Required for Bedrock AgentCore log delivery.
- `sts:GetCallerIdentity`: Required for identity verification.
- `ec2:CreateNetworkInterface`: Required for dynamic VPC networking.
- `s3:ListAllMyBuckets`: Required for bucket discovery.

**Rule**: Every wildcard MUST have a comment: `# AWS-REQUIRED: <Reason>`.

**Exception Change Control**:
- A new wildcard exception is allowed only with a linked AWS primary source proving resource-level scoping is unsupported.
- The policy statement MUST include `# AWS-REQUIRED: <Reason>` and a doc reference in adjacent comments.
- Add/update tests that explicitly validate only the approved wildcard actions.
- Update this "Known Exceptions" list in the same change.

#### Rule 1.2: Errors MUST Fail Fast
Forbidden:
```bash
cp -r "${local.source_path}"/* "$BUILD_DIR/code/" 2>/dev/null || true
```
Required:
```bash
if [ ! -d "${local.source_path}" ]; then
  echo "ERROR: Source path not found: ${local.source_path}"
  exit 1
fi
cp -r "${local.source_path}"/* "$BUILD_DIR/code/"
```

**Why**: Error suppression masks deployment failures.

---

## RULE 2: Module Architecture is FIXED

Dependency direction (IMMUTABLE):
foundation -> tools/runtime -> governance

Module boundaries:
- **foundation**: Gateway, Identity, Observability
- **tools**: Code Interpreter, Browser
- **runtime**: Runtime, Memory, Packaging
- **governance**: Policies, Evaluations

Reference: `docs/architecture.md`

---

## RULE 3: Coding Rules

### Rule 3.1: Terraform
- Prefer `for_each` with stable keys over `count`.
- Use explicit types and validation for all variables.
- Mark secrets as `sensitive = true`.
- Avoid `null_resource` unless using the CLI pattern (Rule 4).

### Rule 3.2: Python (Strands SDK)
- **Target**: Python 3.12 only.
- **Format**: Black + Flake8 (Line length 120).
- **Testing**: `pytest` under `examples/*/agent-code/tests/`.
- **Behavior**: Use `logging` instead of `print`.
- **Mocks**: No network calls in unit tests; mock external services.

---

## RULE 4: CLI Pattern is MANDATORY

The following resources MUST use the `null_resource` + AWS CLI pattern due to provider gaps:
1. Gateway
2. Identity
3. Browser
4. Code Interpreter
5. Runtime
6. Memory
7. Policy Engine / Cedar Policies
8. Evaluators
9. Credential Providers

For the nine resources above, this rule takes precedence over Terraform-native preferences.
For all other resources, follow the decision framework (native provider first when available and stable).

---

## RULE 5: AWS Query Source of Truth (MANDATORY)

### Rule 5.1: AWS Knowledge MCP First
- For any AWS-specific question, agents MUST query `aws-knowledge-mcp-server` before answering.
- This includes: service availability, API/CLI syntax, limits/quotas, pricing, release status, and troubleshooting.
- General memory may be used for context, but final answers MUST be grounded in AWS Knowledge MCP results.
- Fallback: If `aws-knowledge-mcp-server` is unavailable, agents MUST state that explicitly, use best-effort official AWS docs, and mark the answer as lower confidence.

### Rule 5.2: Required Query Flow
1. Choose the first tool by question type:
   - Regional availability: `get_regional_availability`.
   - API/CLI usage, limits, errors, best practices: `search_documentation`.
2. If a specific documentation URL is found or provided, use `read_documentation` on that URL.
3. If results conflict or are unclear, run a second targeted query and state the uncertainty explicitly.
4. Prefer primary AWS documentation pages over secondary summaries.

### Rule 5.3: Response Requirements
- Include the exact check date in the response for time-sensitive AWS facts.
- Include source links (AWS docs/AWS Knowledge MCP-backed URLs).
- Clearly label any inference vs directly confirmed facts.
- Include exact command/API field names when answering implementation questions.
- If fallback mode was used, include: "AWS Knowledge MCP unavailable at query time."

### Rule 5.4: Query Examples
- Availability check:
  - `get_regional_availability(region="eu-west-2", resource_type="product", filters=["Amazon Bedrock AgentCore","Amazon Bedrock AgentCore Runtime"])`
- API/CLI reference:
  - `search_documentation(search_phrase="bedrock-agentcore-control create-gateway", topics=["reference_documentation"])`
- Troubleshooting:
  - `search_documentation(search_phrase="AccessDenied bedrock-agentcore create-gateway-target", topics=["troubleshooting"])`
- Release awareness:
  - `search_documentation(search_phrase="Amazon Bedrock AgentCore new features", topics=["current_awareness"])`

---

## RULE 6: Versioning & Release Freeze (MANDATORY)

### Rule 6.1: Canonical Version Source
- The repository version MUST be stored in the root `VERSION` file using SemVer (`MAJOR.MINOR.PATCH`).
- During the current pre-1.0 phase, the active release line is `0.1.x`.
- Any release change MUST update `VERSION` and `CHANGELOG.md` in the same commit.

### Rule 6.2: Tags Are the Release Artifact
- Official releases MUST be created as immutable Git tags in the format `vMAJOR.MINOR.PATCH` (example: `v0.1.0`).
- Branches are for integration only; tags are the source of truth for Terraform module consumers.
- Forks are NOT a release mechanism for this repo.

### Rule 6.3: Promotion Model
- `main` is the integration branch.
- `main` is also the promotion branch for dev and test; no long-lived `release/*` branch is used in the standard flow.
- Test environment actions (`plan:test`, `deploy:test`, `smoke-test:test`) are allowed only from manual/API pipelines on `main` and require explicit manual promotion first (`promote:test`).
- Production promotion MUST reference a tag that points to the exact tested commit SHA.

### Rule 6.4: GitHub + GitLab Remote Sync
- This repository is dual-remote: `origin` (GitHub) and `gitlab` (GitLab).
- Release commits and release tags MUST be pushed to both remotes.
- Use non-interactive CLI commands only (for example: `git push origin main`, `git push gitlab main`, `git push origin v0.1.0`, `git push gitlab v0.1.0`).
- Validate both CI systems after push: GitHub Actions for validation and GitLab CI for deployment gates.

---

## RULE 7: Documentation Sync & Sprawl Control

### Rule 7.1: Agent Rule Docs Must Match
- `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` MUST remain byte-identical.
- If one file changes, all three MUST be updated in the same commit.

### Rule 7.2: Update Docs Before Commit/Push
- Any behavioral, CI/CD, architecture, or workflow change MUST include the required docs update before commit and before push.
- "Follow-up docs later" is not permitted.

### Rule 7.3: Ephemeral Work Area
- Temporary experiments, generated files, and one-off tooling outputs MUST live under `.scratch/`.
- `.scratch/` content is session-scoped and MUST NOT be committed.
- Reusable automation belongs in existing maintained locations (`terraform/scripts/`, `Makefile`) and requires documentation.

### Rule 7.3.1: `.context/` for Committed Research & Synthesis
- `.context/` is the repository location for committed agent/human research syntheses, reference packs, and project-specific context intended to improve future execution quality.
- `.context/` content MUST be curated and human-readable (summaries, decision notes, source indexes, migration notes), not raw dumps of fetched web pages, binaries, or generated scratch output.
- Every `.context/` pack MUST include:
  - check date(s) for time-sensitive facts,
  - source links (primary sources preferred),
  - clear repo relevance (why this context exists here).
- Raw extraction artifacts, temporary downloads, and one-off parsing outputs MUST remain in `.scratch/` and MUST NOT be committed.
- If workflow/tooling begins to depend on `.context/` content, document that behavior in `README.md` and/or `DEVELOPER_GUIDE.md` in the same change.

### Rule 7.4: No File Proliferation
- Do not create variant files like `*_v2.*`, `*_improved.*`, `*_enhanced.*`, `*_copy.*`, `*_tmp.*`, or `*_backup.*`.
- Prefer editing existing files in place.
- A new file is allowed only when it introduces genuinely new functionality that cannot fit an existing file without reducing clarity.

### Rule 7.5: Script Sprawl Control
- Committed automation scripts are allowed only in established locations (`terraform/scripts/`, CI workflows, or template/example agent-code paths).
- One-off scripts for investigation/migration must be created under `.scratch/` and must remain uncommitted.

### Rule 7.6: New-File Accountability
- Any committed new file MUST be accompanied by:
  - a short rationale in the commit message, and
  - required docs updates in the same commit when behavior/workflow changes.

### Rule 7.7: Startup Preflight is Mandatory
- Session startup/worktree safety checks are governed by the repo SoT file: `terraform/scripts/session/preflight.policy`.
- Agents and humans MUST run `make preflight-session` at session start and before commit/push.
- If preflight fails, do not proceed with edits/commits until resolved.

### Rule 7.8: Worktree Finish & Cleanup
- A worktree is **not finished** when code is only local or locally validated.
- A worktree is finished only when the issue closure condition has been met (for example `PR merged`) and any required issue/PR evidence updates are posted.
- Agents MUST track and report the current finish stage when pausing or handing off. Use these stages:
  - `implementing` (editing/validating in worktree),
  - `ready-to-commit`,
  - `ready-to-push`,
  - `pr-open`,
  - `review`,
  - `merged`,
  - `cleanup-complete`.
- Do not remove a linked worktree until its branch is pushed and no local-only work remains.
- After merge to `main`, agents SHOULD remove the linked worktree, delete the local branch, and run `git worktree prune`.
- Worktree cleanup MUST NOT discard unmerged or unpushed changes.

---

## RULE 9: Discovery is EXPLICIT

### Rule 9.1: Agents Must Be Discoverable
- **Requirement**: Every agent MUST expose `/.well-known/agent-card.json`.
- **Registry**: Agents MUST register with **Cloud Map** (East-West) or the **Gateway Manifest** (Northbound).

### Rule 9.2: Gateway is the Tool Source
- **Requirement**: Tools MUST be accessed via the **AgentCore Gateway**.
- **Forbidden**: Invoking Tool Lambdas directly via `lambda:InvokeFunction`.

---

## RULE 10: Identity Propagation is MANDATORY

### Rule 10.1: No Anonymous A2A Calls
- **Requirement**: Agent-to-Agent calls MUST use a **Workload Token**.
- **Pattern**: `GetWorkloadAccessTokenForJWT` -> `Authorization: Bearer <token>`.

### Rule 10.2: User Context Must Persist
- **Requirement**: Original Entra ID context MUST be exchanged, not dropped.

---

## RULE 11: Frontend Security (Token Handler)

### Rule 11.1: No Tokens in Browser
- **Forbidden**: Storing Access/Refresh Tokens in `localStorage`, `sessionStorage`, or Cookies accessible to JS.
- **Requirement**: Tokens must be stored server-side (DynamoDB/ElastiCache).

### Rule 11.2: Session Management
- **Pattern**: Use **Secure, HTTP-only, SameSite=Strict** cookies for Session IDs.
- **Reference**: ADR 0011 (Serverless Token Handler).

---

## RULE 12: Comprehensive Issue Reporting

### Rule 12.1: Issue Structure
AI Agents MUST create comprehensive GitHub issues. Every issue MUST include:
- **Context**: Why is this change needed? (Relate to ADRs/Rules).
- **Technical Detail**: Specific AWS APIs, Python libraries, or Terraform patterns to be used.
- **Implementation Tasks**: A checklist of specific actionable items.
- **Acceptance Criteria**: Verifiable outcomes (e.g., "Exit code 0", "Test passes").

### Rule 12.2: Roadmap Alignment
- Every planned item in `ROADMAP.md` MUST have a corresponding GitHub Issue.
- The Roadmap provides the **Strategic Vision**; Issues provide the **Execution Detail**.
- When an issue is closed, the corresponding item in `ROADMAP.md` MUST be ticked.

### Rule 12.3: Tracker Issues vs Execution Issues (MANDATORY)
- A **Tracker Issue** coordinates a larger initiative (scope, sequencing, blockers, child issues, status rollup).
- An **Execution Issue** is a single implementable work package assigned to one agent/worktree.
- Agents MUST perform implementation work against an Execution Issue, not a Tracker Issue, unless the task is explicitly planning/docs-only.

### Rule 12.4: Worktree Branch Issue ID MUST Match the Execution Issue
- Linked worktree branch names (`wt/<scope>/<issue>-<slug>`) MUST use the **Execution Issue** number.
- Tracker Issue numbers MUST NOT be used for implementation branches unless the work is planning/docs-only for the tracker itself.

### Rule 12.5: One Agent / One Execution Issue / One Worktree
- Each active coding agent MUST be assigned exactly one open Execution Issue at a time.
- Each active Execution Issue MUST map to exactly one worktree and one branch.
- Do not allocate parallel agents to tasks with high-overlap file paths unless explicitly coordinated.

### Rule 12.6: Tracker-Agent Completion Criteria
- An agent assigned to a Tracker Issue is done when the work is allocatable:
  - child Execution Issues created/updated with full Rule 12.1 structure,
  - dependencies and ordering documented,
  - ready tasks labeled,
  - active allocations recorded,
  - blockers explicitly captured.
- Tracker agents SHOULD stop after coordination outputs unless the tracker is explicitly a planning/docs implementation task.

### Rule 12.7: Allocation Status Labels (Standard)
- Use labels for execution state: `ready`, `in-progress`, `blocked`, `review`, `done`.
- Workstream lane labels (roadmap-aligned) are: `a`, `b`, `c`, `d`, `e`.
- Roadmap item labels (optional) are labels like `a0`, `a1`, `b0`, `c2`, `d1`, `e3`.
- Optional domain/topic labels (for example `provider-matrix`, `freeze-point`) MAY be used for filtering and reporting.

### Rule 12.8: Execution Issue Finish Protocol (MANDATORY)
For any Execution Issue, agents MUST complete the following finish sequence:
1. Run `make preflight-session`.
2. Run issue-appropriate validation (and required repo checks for the touched scope).
3. Commit focused changes with the issue number in the commit message.
4. Push the worktree branch to `origin` (and other remotes only if required by team convention).
5. Open or update a PR to `main`.
6. Post a closeout comment on the issue including:
   - summary of changes,
   - validation commands run and outcomes,
   - evidence links (PR, commit SHA, CI).
7. Update issue labels/status (`in-progress` -> `review` or `done`).
8. Close the issue only after merge unless the team workflow explicitly closes on PR creation.
- Agents MUST NOT mark an Execution Issue complete based only on local edits or local validation.
- If pausing before merge, agents MUST report:
  - current finish stage (Rule 7.8),
  - what is already complete,
  - exact next command(s) to advance the issue.

### Rule 12.9: Tracker Issue Finish Protocol (MANDATORY)
For Tracker Issues, agents are done when work is allocatable or fully coordinated:
- child Execution Issues created/updated with Rule 12.1 structure,
- dependencies and ordering documented,
- ready tasks labeled,
- active allocations recorded,
- blockers captured,
- tracker checklist/status updated.
Tracker agents SHOULD NOT perform implementation work unless the tracker is explicitly a planning/docs implementation task.

### Rule 12.10: Definition of Done Must Be Explicit
Every issue MUST define completion evidence:
- required validation commands,
- expected outcomes,
- required docs updates,
- closure condition (PR opened, PR merged, or release tag).

### Rule 12.11: Label Hygiene for Queueing (MANDATORY)
- This rule is the source of truth for issue label taxonomy used by the `ready` queue and `make worktree`.
- The `ready` queue is a scheduling mechanism and MUST remain high-signal.
- Issues used for agent allocation MUST maintain label hygiene before they are marked `ready`.
- Every allocatable issue MUST have:
  - exactly one issue-type label: `tracker` or `execution`,
  - exactly one status label from: `ready`, `in-progress`, `blocked`, `review`, `done`.
- Roadmap-planned issues MUST include exactly one workstream lane label (`a`, `b`, `c`, `d`, or `e`).
- Roadmap item labels (for example `a0`, `a1`, `b0`) are RECOMMENDED for roadmap parity and queue readability, but optional.
- Priority labels are optional, but if used MUST be singular (for example one of `p0`, `p1`, `p2`, `p3`).
- Do not use duplicate/synonym labels for the same meaning (for example multiple competing status labels).
- Status transitions MUST remove the previous status label in the same update (for example `ready` -> `in-progress`).
- An issue MUST NOT be labeled `ready` unless:
  - Rule 12.1 structure is complete,
  - dependencies/blockers are explicit,
  - acceptance criteria are actionable,
  - closure condition is stated,
  - the issue is allocatable to one agent/worktree.
- Trackers MAY be labeled `ready` only when they are ready for coordination work (not implementation execution) and the intended outcome is clear.

---

## RULE 13: Repo Layout & Reorg Guardrails

**Layout**: Terraform core is in `terraform/`. Examples live in `examples/`. Docs live at repo root and `docs/`.

**Rules**:
- Do not move docs into `terraform/`.
- Keep examples adjacent at repo root.
- If you move Terraform files, update references in `README.md`, `DEVELOPER_GUIDE.md`, `Makefile`, `validate_windows.bat`, `scripts/`, and `tests/`.
- Run the preflight tests in `docs/runbooks/repo-restructure.md` before and after any move.

---

## DECISION FRAMEWORK

| Question | Answer |
| --- | --- |
| Terraform-native or CLI? | Gateway/Identity/Browser/Code Interpreter/Runtime/Memory/Policy Engine/Evaluators/Credential Providers: CLI pattern mandatory (Rule 4). All others: use native provider if available and stable; otherwise use CLI pattern. |
| Which module? | Foundation, Tools, Runtime, Governance (Fixed architecture). |
| Use dynamic block? | Only for repeatable blocks. NEVER for single attributes. |
| KMS or AWS-managed? | AWS-managed (SSE-S3) by default. |
| Hardcode ARNs/regions? | NEVER. Use data sources or module outputs. |
| Where do tokens go? | DynamoDB (server-side). Never in the browser. |

---

## CHECKLIST: Before Every Commit

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan -backend=false -var-file=../examples/research-agent.tfvars
checkov -d terraform --framework terraform --compact --config-file terraform/.checkov.yaml
tflint --chdir=terraform --recursive --config terraform/.tflint.hcl
pre-commit run --all-files
```

### Windows Notes (Pre-commit + Terraform Hooks)
- Terraform-related pre-commit hooks require **bash**. On Windows, run `pre-commit` from **Git Bash or WSL** for full checks.
- For a Windows-native minimal check, use `validate_windows.bat` (runs `terraform fmt` + `pre-commit` with Terraform hooks skipped).

### YAML Rule for Pre-commit Entries
- If a `pre-commit` hook `entry:` contains `:` or complex shell, use a block scalar (`>-`) to avoid YAML parse errors.

### Binary Hygiene
- Do not commit tool binaries. Keep `.tools/` ignored and download tooling via scripts when needed.

---

## KEY DECISIONS (ADRs)

| ADR | Decision | Rationale |
|-----|----------|-----------|
| 0001 | 4-module architecture | Clear separation of concerns |
| 0002 | CLI-based resources | AWS provider gaps |
| 0008 | AWS-managed encryption | Simpler, equivalent security |
| 0009 | B2E Publishing & Identity | Streaming + Entra ID |
| 0010 | Service Discovery (Dual-Tier) | Cloud Map + Registry |
| 0011 | Serverless SPA & BFF | Token Handler Pattern (No XSS) |

---

## RULE 14: Multi-Tenant Isolation (MANDATORY)

### Rule 14.1: No Implicit Tenant Trust
- **Requirement**: Components MUST NOT trust a `tenant_id` or `session_id` provided in the request body without verifying it against the authenticated OIDC context (JWT claims).
- **Enforcement**: The `Agent Proxy` MUST validate that the `sessionId` belongs to the `tenant_id` and `app_id` extracted from the authorizer context.

### Rule 14.2: Partitioned Storage
- **Requirement**: All persistent state (S3 Memory, DynamoDB Sessions) MUST be partitioned by `app_id` and `tenant_id`.
- **Pattern (S3)**: `s3://{bucket}/{app_id}/{tenant_id}/{agent_name}/memory/`.
- **Pattern (DynamoDB)**:
  - `PartitionKey (PK)`: `APP#{app_id}#TENANT#{tenant_id}`
  - `SortKey (SK)`: `SESSION#{session_id}`

### Rule 14.3: ABAC Enforcement
- **Requirement**: Access to resources MUST be restricted using **Attribute-Based Access Control (ABAC)**.
- **Implementation**: IAM and Cedar policies MUST use conditions comparing the `principal.tenant_id` with the `resource.tenant_id`.
- **Example**:
  ```hcl
  Condition = {
    StringEquals = { "s3:ExistingObjectTag/TenantID" = "${aws:PrincipalTag/TenantID}" }
  }
  ```

### Rule 14.4: Hierarchical Identity (North-South Join)
- **Requirement**: Every interaction MUST be anchored by the North-South hierarchy.
- **North Anchor**: `AppID` (Logical application/environment boundary).
- **Middle Anchor**: `TenantID` (Unit of ownership).
- **South Anchor**: `AgentName` (Physical compute resource).
- **Join Logic**: `Identity = [AppID] + [TenantID]`, `Compute = [AgentName]`.

### Rule 14.5: Just-in-Time (ZTO) Onboarding
- **Requirement**: Tenant-specific logical resources (S3 prefixes, DDB items) MUST be provisioned just-in-time upon first successful OIDC authentication.
