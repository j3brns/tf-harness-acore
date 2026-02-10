# Development Rules & Principles for AI Coding Agents
## Bedrock AgentCore Terraform

> **Critical**: This is NOT a typical Terraform project. Read ALL rules before making ANY changes.

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
- **Remediation Plan**: `docs/plans/REMEDIATION_PLAN_V1.md`
- **ADRs**: `docs/adr/`
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
Every wildcard MUST have a comment: `# AWS-REQUIRED: <Reason>`.

#### Rule 1.2: Errors MUST Fail Fast
Provisioners MUST check output files: `if [ ! -s "file.json" ]; then exit 1; fi`.

#### Rule 1.8: Bedrock Guardrails (Secure by Default)
- **Policy**: Bedrock Guardrails are ENABLED by default for all agent aliases.
- **Active Rejection**: Disabling guardrails requires an explicit `enable_guardrails = false` toggle AND a documented justification.

---

## RULE 2: Module Architecture is FIXED

Dependency direction (IMMUTABLE):
foundation -> tools/runtime -> governance

Reference: `docs/architecture.md`

---

## RULE 3: Coding Rules

### Rule 3.1: Terraform
- Prefer `for_each` with stable keys over `count`.
- Use explicit types and validation for all variables.
- Mark secrets as `sensitive = true`.

### Rule 3.2: Python (Strands SDK)
- **Target**: Python 3.12 only.
- **Format**: Black + Flake8 (Line length 120).
- **Testing**: `pytest` under `examples/*/agent-code/tests/`.

---

## RULE 4: CLI Pattern is MANDATORY

The following resources MUST use the `null_resource` + AWS CLI pattern:
1. Gateway, 2. Identity, 3. Browser, 4. Code Interpreter, 5. Runtime, 6. Memory, 7. Policy Engine, 8. Evaluators, 9. Credential Providers.

---

## RULE 5: SSM State Persistence (Zero Local IDs)

### Rule 5.1: No Ephemeral IDs
- **Problem**: Local JSON files in `.terraform/` are lost in CI/CD.
- **Requirement**: ALL resource IDs created via CLI MUST be persisted to **AWS SSM Parameter Store**.
- **Pattern**: 
  1. CLI creates resource and captures ID.
  2. CLI calls `aws ssm put-parameter --name "/agentcore/${var.agent_name}/<resource_type>/id" --value "$ID"`.
  3. Subsequent resources use `data "aws_ssm_parameter"` to retrieve the ID.

---

## RULE 6: Zombie Resource Prevention (Cleanup Hooks)

### Rule 6.1: Mandatory Destroy Provisioners
- **Problem**: `null_resource` does not automatically delete AWS resources on `terraform destroy`.
- **Requirement**: Every `null_resource` MUST include a `destroy` provisioner.
- **Implementation**:
  ```hcl
  provisioner "local-exec" {
    when    = destroy
    command = "aws bedrock-agentcore-control delete-... --id ${self.triggers.resource_id}"
  }
  ```
- **Constraint**: Use `triggers` to pass the ID into the destroy context.

---

## RULE 7: Zero Trust Identity (ABAC Scoping)

### Rule 7.1: Attribute-Based Trust
- **Requirement**: Agent identity roles MUST NOT use name-based wildcards for trust relationships.
- **Enforcement**: Use **Attribute-Based Access Control (ABAC)** tags.
- **Policy**: `Condition = { StringEquals = { "aws:PrincipalTag/Project" = "${var.project_tag}" } }`.

---

## RULE 11: Frontend Security (Token Handler)

### Rule 11.1: No Tokens in Browser
- **Forbidden**: Storing tokens in `localStorage` or JS-accessible cookies.
- **Requirement**: Tokens must be stored server-side.

---

## RULE 12: Issue Reporting & Verification

### Rule 12.3: Post-Commit Verification
- **Mandatory**: After every `git push`, AI agents MUST check the CI logs (`gh run list/view`).
- **Action**: If CI fails, the agent MUST investigate and fix the root cause in the next turn.

---

## RULE 13: Example Parity
- **Requirement**: Any change to a core module MUST be accompanied by an update to at least one example in `examples/`.
- **Goal**: Demonstrate new functionality and ensure backward compatibility.

---

## RULE 14: Read-After-Write (RAW) Verification
- **Requirement**: After any `write_file` or `replace` operation, the agent MUST immediately `read_file` the affected section.
- **Goal**: Verify correct implementation and catch formatting regressions immediately.

---

## RULE 15: Shadow JSON Validation
- **Requirement**: All CLI-based resources (`null_resource`) MUST generate their AWS CLI JSON payload to a temporary file (e.g., `.terraform/payload.json`) before execution.
- **Goal**: Enable auditability of exact data sent to AWS APIs.

---

## RULE 16: Failure Mode Documentation
- **Requirement**: Every module's `README.md` MUST contain a "Known Failure Modes" section.
- **Content**: Detail manual recovery steps for CLI/provisioner failures (e.g., SSM parameter cleanup).

## RULE 17: Template Integrity & Parity
- **Trigger**: Any modification to `terraform/variables.tf`, `terraform/main.tf`, or module interfaces.
- **Requirement**: You MUST update `templates/agent-project` to reflect the change.
- **Verification**: The `template-test` CI job must pass (generates a fresh project and runs validation).
- **Definition of Done**: A feature is not complete until it works in the Core Modules, The Examples, *AND* The Template.

---

## DECISION FRAMEWORK

| Question | Answer |
| --- | --- |
| Where do IDs go? | persisted to AWS SSM Parameter Store (Rule 5). |
| How to delete? | Mandatory `when = destroy` provisioner (Rule 6). |
| How to trust? | ABAC tags, never name-wildcards (Rule 7). |
| KMS or AWS-managed? | AWS-managed (SSE-S3) by default. |

---

## CHECKLIST: Before Every Commit

```bash
terraform fmt -check -recursive
terraform validate
tflint --recursive
gh run list --limit 1 # Post-push check (Rule 12.3)
```