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

---

## DECISION FRAMEWORK

| Question | Answer |
| --- | --- |
| Terraform-native or CLI? | If `aws_bedrockagentcore_X` exists AND passes `terraform validate`, use native. Otherwise use CLI pattern. |
| Which module? | Foundation, Tools, Runtime, Governance (Fixed architecture). |
| Use dynamic block? | Only for repeatable blocks. NEVER for single attributes. |
| KMS or AWS-managed? | AWS-managed (SSE-S3) by default. |
| Hardcode ARNs/regions? | NEVER. Use data sources or module outputs. |
| Where do tokens go? | DynamoDB (server-side). Never in the browser. |

---

## CHECKLIST: Before Every Commit

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -backend=false -var-file=examples/research-agent.tfvars
checkov -d . --framework terraform --compact
tflint --recursive
pre-commit run --all-files
```

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
