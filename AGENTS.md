# Development Rules & Principles for AI Coding Agents
## Bedrock AgentCore Terraform

> **Critical**: This is NOT a typical Terraform project. Read ALL rules before making ANY changes.

---

## RULE 1: Security is NON-NEGOTIABLE

### Critical Security Findings (From Senior Engineer Review)

**DEPLOYMENT BLOCKERS identified and remediated**:
1. IAM wildcard resources (3 instances) - REMEDIATED: Scoped to specific ARNs (where AWS allows) or documented as AWS-required exceptions.
2. Dynamic block syntax errors - FIXED: Replaced with direct attributes
3. Error suppression masking failures - FIXED: Implemented fail-fast error handling in all provisioners
4. Placeholder ARN validation missing - FIXED: Added variable validation
5. Dependency package limits - FIXED: Removed head -20 limit

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

**Why**: Wildcard resources violate least privilege.

**When to apply**: EVERY IAM policy. No exceptions.

#### Rule 1.2: Errors MUST Fail Fast
```bash
# FORBIDDEN:
cp -r "${local.source_path}"/* "$BUILD_DIR/code/" 2>/dev/null || true

# REQUIRED:
if [ ! -d "${local.source_path}" ]; then
  echo "ERROR: Source path not found: ${local.source_path}"
  exit 1
fi
cp -r "${local.source_path}"/* "$BUILD_DIR/code/"
```

**Why**: Error suppression (`|| true`, `2>/dev/null`) masks deployment failures.

**When to apply**: ALL bash provisioners in `null_resource` blocks.

#### Rule 1.3: Dynamic Blocks Only for Collections
```hcl
# FORBIDDEN:
dynamic "kms_key_arn" {
  for_each = var.enable_kms ? [aws_kms_key.agentcore[0].arn] : []
  content {
    value = kms_key_arn.value
  }
}

# REQUIRED:
kms_key_arn = var.enable_kms ? aws_kms_key.agentcore[0].arn : null
```

**Why**: `dynamic` is for blocks, not simple attributes.

**When to apply**: Use `dynamic` ONLY for repeatable blocks, NEVER for single attributes.

#### Rule 1.4: Validate ALL User Inputs
```hcl
# REQUIRED:
variable "mcp_targets" {
  validation {
    condition = alltrue([
      for k, v in var.mcp_targets :
      !can(regex("123456789012", v.lambda_arn))
    ])
    error_message = "Placeholder ARNs detected. Replace with actual account ID."
  }
}
```

**Why**: Placeholder ARNs in examples cause production failures.

**When to apply**: ALL variables accepting ARNs, URLs, or account IDs.

#### Rule 1.5: No Arbitrary Limits
```bash
# FORBIDDEN:
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}" | head -20)

# REQUIRED:
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
```

**Why**: `head -20` artificially limits dependencies.

**When to apply**: NEVER use `head`/`tail` unless explicitly paginating.

#### Rule 1.6: Use AWS-Managed Encryption
```hcl
# PREFERRED:
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # AWS-managed SSE-S3
    }
  }
}

# AVOID (unless regulatory requirements mandate it):
resource "aws_kms_key" "custom" {
  # Customer-managed KMS adds complexity without security benefit
}
```

**Why**: AWS-managed encryption (SSE-S3, default CloudWatch encryption) provides equivalent security with less operational overhead. Customer-managed KMS introduces key management complexity and cost.

**When to apply**: Use AWS-managed encryption by default. Only use customer-managed KMS when:
- Regulatory requirements mandate customer-controlled keys
- Cross-account encryption is needed
- Custom key rotation schedules are required

**Reference**: See ADR `docs/adr/0008-aws-managed-encryption.md` for full rationale.

#### Rule 1.7: NEVER Hardcode ARNs or Regions
```hcl
# FORBIDDEN:
lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:my-function"
region     = "us-east-1"

# REQUIRED - Use data sources:
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

lambda_arn = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.function_name}"

# REQUIRED - For cross-module references, use module outputs:
module "mcp_servers" {
  source = "./examples/mcp-servers/terraform"
}

mcp_targets = module.mcp_servers.mcp_targets  # ARNs resolved automatically

# REQUIRED - For existing resources, use data sources:
data "aws_lambda_function" "existing" {
  function_name = var.function_name
}

lambda_arn = data.aws_lambda_function.existing.arn
```

**Why**: Hardcoded ARNs break when:
- Deploying to different accounts (dev/test/prod)
- Deploying to different regions
- Sharing code with other teams
- Placeholder values (123456789012) reach production

**When to apply**:
- ALL ARN references in Terraform code
- ALL region references in Terraform code
- ALL account ID references in Terraform code

**Patterns by Use Case**:

| Use Case | Pattern |
|----------|---------|
| Reference own resources | Use resource attributes: `aws_lambda_function.my_func.arn` |
| Cross-module reference | Use module outputs: `module.mcp_servers.mcp_targets` |
| Reference existing resources | Use data sources: `data.aws_lambda_function.existing.arn` |
| Build ARNs dynamically | Use `data.aws_caller_identity` + `data.aws_region` |
| Example tfvars files | Document "replace with output from X" or use variables |

**Reference**: See `examples/5-integrated/` for the recommended module composition pattern.

### Security Checklist - Run Before EVERY Commit
```bash
# 1. Format check
terraform fmt -check -recursive

# 2. Syntax validation
terraform validate

# 3. Security scan (MUST be clean)
checkov -d . --framework terraform --compact

# 4. Lint (best practices)
tflint --recursive

# EXIT CODE 0 REQUIRED FOR ALL
```

---

## RULE 2: Module Architecture is FIXED

### Dependency Graph (IMMUTABLE)
```
agentcore-foundation (NO dependencies)
    |
    +---> agentcore-tools (depends: foundation)
    +---> agentcore-runtime (depends: foundation)
    |         |
    |     agentcore-governance (depends: foundation + runtime)
    +---> agentcore-governance (depends: foundation + runtime)
```

### Rule 2.1: Dependency Direction NEVER Reverses
- FORBIDDEN: Runtime depending on Governance
- FORBIDDEN: Foundation depending on any other module
- ALLOWED: Governance depending on Runtime

**Why**: Circular dependencies break Terraform. Foundation is the base layer.

### Rule 2.2: Module Boundaries Are Semantic
- **foundation**: Infrastructure primitives (Gateway, Identity, Observability)
- **tools**: Agent capabilities (Code Interpreter, Browser)
- **runtime**: Execution lifecycle (Runtime, Memory, Packaging)
- **governance**: Security & quality (Policies, Evaluations)

**Rule**: If a resource doesn't fit semantically, DON'T force it. Ask for guidance.

---

## RULE 3: CLI-Based Resources Follow Strict Pattern

### The 7 CLI-Based Resources
Due to AWS provider gaps, these resources use `null_resource` + AWS CLI:
1. Runtime (`bedrock-agentcore-control create-agent-runtime`)
2. Memory (`bedrock-agentcore-control create-memory`)
3. Policy Engine (`bedrock-agentcore-control create-policy-engine`)
4. Cedar Policies (`bedrock-agentcore-control create-policy`)
5. Evaluators (`bedrock-agentcore-control create-evaluator`)
6. OAuth2 Providers (`bedrock-agentcore-control create-oauth2-credential-provider`)
7. Credential Providers (various `bedrock-agentcore-control` commands)

### Rule 3.1: CLI Pattern is MANDATORY
```hcl
# REQUIRED PATTERN:
resource "null_resource" "resource_name" {
  triggers = {
    # Hash-based change detection
    config_hash = sha256(jsonencode(var.resource_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Fail fast (no error suppression)
      set -e

      aws bedrock-agentcore-control create-X \
        --name ${var.resource_name} \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/output.json

      # Verify output was created
      if [ ! -f "${path.module}/.terraform/output.json" ]; then
        echo "ERROR: Command failed - no output file"
        exit 1
      fi
    EOT
  }
}

data "external" "resource_output" {
  program = ["cat", "${path.module}/.terraform/output.json"]
  depends_on = [null_resource.resource_name]
}

output "resource_id" {
  value = data.external.resource_output.result.resourceId
}
```

### Rule 3.2: Migration Path is Documented
When AWS provider adds native resources:
1. `terraform import aws_bedrockagentcore_X.main <id>`
2. Replace `null_resource` with native resource
3. Update outputs to use native attributes
4. Test with `terraform plan` (should show NO changes)
5. Remove `.terraform/*.json` files

**Critical**: NEVER skip the import step or state will be lost.

---

## RULE 4: Testing is LOCAL-FIRST

### Rule 4.1: Developers NEVER Need AWS for Validation
```bash
# These commands run locally, NO AWS account required:
terraform fmt -check
terraform validate
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars
tflint
checkov
```

**Why**: AWS costs money and slows development. Local validation catches 95% of issues.

### Rule 4.2: CI Pipeline Stages Are Ordered
```
Stage 1: validate (fmt, validate, plan) --> NO AWS
Stage 2: lint (tflint, checkov)         --> NO AWS
Stage 3: test (examples, policies)      --> NO AWS
Stage 4: deploy-dev (auto)              --> AWS DEV account
Stage 5: deploy-test (manual)           --> AWS TEST account
Stage 6: deploy-prod (manual)           --> AWS PROD account
```

**Rule**: Stages 1-3 MUST pass before ANY AWS deployment.

### Rule 4.3: Example Validation is MANDATORY
Every new example MUST:
1. Have corresponding test in `scripts/validate_examples.sh`
2. Pass `terraform plan` without errors
3. Not use placeholder ARNs (validation enforced)
4. Include README explaining purpose

---

## RULE 5: Two-Stage Build is OCDS-Compliant

### Rule 5.1: Build Stages Are Sequential
```bash
# Stage 1: Dependencies (cached)
BUILD_DIR=$(mktemp -d)
DEPS_DIR="$BUILD_DIR/deps"
pip install -t "$DEPS_DIR" -r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")

# Stage 2: Code (always fresh)
CODE_DIR="$BUILD_DIR/code"
cp -r "${local.source_path}"/* "$CODE_DIR/"

# Package
cd "$BUILD_DIR"
zip -r deployment.zip deps/ code/
```

**Why**: OCDS pattern separates slow deps from fast code changes.

### Rule 5.2: Hash-Based Triggers Are REQUIRED
```hcl
triggers = {
  dependencies_hash = filemd5(local.dependencies_file)
  source_hash = sha256(join("", [for f in fileset(local.source_path, "**") : filesha256("${local.source_path}/${f}")]))
}
```

**Why**: Without hashes, Terraform can't detect changes.

---

## RULE 6: GitLab CI Uses WIF, Not Credentials

### Rule 6.1: NEVER Store AWS Credentials in GitLab
- FORBIDDEN: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` in CI/CD variables
- REQUIRED: Web Identity Federation with OIDC

**Setup**:
```yaml
before_script:
  - export AWS_ROLE_ARN=${CI_ENVIRONMENT_ROLE_ARN}
  - export AWS_WEB_IDENTITY_TOKEN_FILE=${GITLAB_TOKEN_FILE}
  - aws sts get-caller-identity  # Verify WIF works
```

**Why**: Static credentials are a security risk. WIF provides temporary, scoped credentials.

### Rule 6.2: State Per Environment, Not Per Branch
```hcl
# CORRECT:
terraform {
  backend "s3" {
    bucket = "terraform-state-dev-12345"   # Dev account
    key    = "agentcore/terraform.tfstate"
  }
}

# FORBIDDEN:
terraform {
  backend "s3" {
    bucket = "shared-state"
    key    = "agentcore/${var.environment}/terraform.tfstate"  # Don't interpolate
  }
}
```

**Why**: Separate AWS accounts = separate state buckets.

---

## RULE 7: Documentation MUST Match Code (ENFORCED)

### The Sync Rule
**Every code change MUST have corresponding documentation update in the SAME commit.**

### What Must Stay In Sync

| Code Change | Required Doc Update |
|-------------|---------------------|
| New variable | README.md variables table + CLAUDE.md if security-related |
| New resource | architecture.md + module README |
| Bug fix | CLAUDE.md anti-patterns (if security) |
| New module | architecture.md + CLAUDE.md module section |
| New example | README.md examples section |
| API change | All affected docs |
| Security decision | ADR in docs/adr/ |

---

## RULE 8: Common Tasks Have Standard Procedures

### Adding a New Variable
1. Add to module's `variables.tf` with validation block
2. Add to root `variables.tf`
3. Add to `terraform.tfvars.example` with comments
4. Update README.md Quick Reference section
5. Add test case to `tests/validation/`
6. Run `terraform validate` + Checkov

### Adding a New Resource
1. Check AWS provider docs: Is it Terraform-native or CLI-based?
2. If Terraform-native: standard resource block
3. If CLI-based: use Rule 3.1 pattern (null_resource + data.external)
4. Add outputs for resource ID/ARN
5. Update module README
6. Run `terraform validate`
7. Run Checkov (must pass)

### Fixing a Security Issue
1. Check `docs/adr/` for related decisions
2. Reference the security checklist in Rule 1
3. Apply fix per applicable Rule 1.x
4. Test: `checkov -d . --framework terraform`
5. Verify: `terraform validate && terraform plan`
6. Update docs with fix details in SAME commit
7. Create ADR if architectural decision was made

### Creating a New Example
1. Create `examples/N-name/agent-code/runtime.py`
2. Create `examples/N-name/terraform.tfvars`
3. Test: `terraform plan -var-file=examples/N-name/terraform.tfvars`
4. Add validation to `scripts/validate_examples.sh`
5. Document in `examples/N-name/README.md`

## RULE 9: Discovery is EXPLICIT

### Rule 9.1: Agents Must Be Discoverable
- **Requirement:** Every agent MUST expose `/.well-known/agent-card.json`.
- **Registry:** Agents MUST register with **Cloud Map** (East-West) or the **Gateway Manifest** (Northbound).
- **Forbidden:** Hardcoding agent endpoints in application code.

### Rule 9.2: Gateway is the Tool Source
- **Requirement:** Tools (Lambda functions) MUST be accessed via the **AgentCore Gateway**.
- **Forbidden:** Agents invoking Tool Lambdas directly via `lambda:InvokeFunction`.

---

## RULE 10: Identity Propagation is MANDATORY

### Rule 10.1: No Anonymous A2A Calls
- **Requirement:** All Agent-to-Agent calls MUST use a **Workload Token**.
- **Pattern:** `GetWorkloadAccessTokenForJWT` -> `Authorization: Bearer <token>`.

### Rule 10.2: User Context Must Persist
- **Requirement:** The original user's identity (Entra ID) MUST be exchanged, not dropped.
- **Why:** To enforce Guardrails and Policies at the destination agent.

---

## DECISION FRAMEWORK

| Question | Answer |
|----------|--------|
| Terraform-native or CLI? | Check if `aws_bedrockagentcore_X` exists. If YES: native. If NO: CLI pattern (Rule 3.1) |
| Which module? | Foundation=Gateway/Identity/Observability, Tools=CodeInterpreter/Browser, Runtime=Runtime/Memory/S3, Governance=Policies/Evaluations |
| Use dynamic block? | ONLY for repeatable blocks (ingress rules). NEVER for simple attributes. |
| New module? | NO. 4-module architecture is fixed. Ask if unsure. |
| KMS or AWS-managed? | AWS-managed (SSE-S3) unless regulatory requirement mandates customer-managed keys |
| Hardcode ARN/region? | NEVER. Use data sources (`aws_caller_identity`, `aws_region`) or module outputs. See Rule 1.7 |
| Reference Lambda ARN? | Use `module.x.lambda_arn` output, NOT hardcoded string. For existing: use `data.aws_lambda_function` |
| Reference S3 bucket? | Use `aws_s3_bucket.x.arn` or `data.aws_s3_bucket.x.arn`. NEVER hardcode bucket names with account IDs |

---

## FILE ORGANIZATION: Key Locations

```
terraform/
+-- modules/                    # 4 core modules (MR required for changes)
|   +-- agentcore-foundation/   # Gateway, Identity, Observability
|   +-- agentcore-tools/        # Code Interpreter, Browser
|   +-- agentcore-runtime/      # Runtime, Memory, Packaging
|   +-- agentcore-governance/   # Policies, Evaluations
+-- examples/                   # Working examples
+-- tests/                      # validation/ and security/ tests
+-- docs/adr/                   # Architecture Decision Records
+-- scripts/                    # Helper utilities
+-- CLAUDE.md                   # This file (AI agent rules)
+-- DEVELOPER_GUIDE.md          # Human onboarding
+-- README.md                   # User documentation
+-- .terraform-version          # Pinned Terraform version (1.14.4)
```

---

## CHECKLIST: Before Every Commit

```bash
# 1. Format (MUST pass)
terraform fmt -check -recursive

# 2. Validate (MUST pass)
terraform validate

# 3. Plan (MUST succeed)
terraform plan -backend=false -var-file=examples/research-agent.tfvars

# 4. Security (MUST be clean)
checkov -d . --framework terraform --compact

# 5. Lint (MUST pass)
tflint --recursive

# 6. Pre-commit hooks (MUST pass)
pre-commit run --all-files

# ALL MUST PASS BEFORE PUSHING
```

---

## VERSION REQUIREMENTS

- **Terraform**: `1.14.4` (pinned via `.terraform-version` - requires >= 1.10.0 for native S3 locking)
- **AWS Provider**: `~> 5.80` (allows 5.80.x and above)
- **null Provider**: `~> 3.2`
- **external Provider**: `~> 2.3`
- **Python**: 3.12 (for agent code)
- **AWS CLI**: >= 2.0
- **Checkov**: >= 3.0
- **TFLint**: >= 0.50

---

## KEY DECISIONS (ADRs)

| ADR | Decision | Rationale |
|-----|----------|-----------|
| 0001 | 4-module architecture | Clear separation of concerns |
| 0002 | CLI-based resources | AWS provider gaps |
| 0003 | GitLab CI with WIF | No static credentials |
| 0004 | S3 backend per environment | State isolation |
| 0005 | Hybrid secrets management | Security + convenience |
| 0006 | Separate backends (not workspaces) | Blast radius containment |
| 0007 | Single region | Cost vs complexity tradeoff |
| 0008 | AWS-managed encryption | Simpler, equivalent security |

---

## GETTING HELP

1. **This file** (CLAUDE.md) - Rules and principles
2. **docs/architecture.md** - System design and data flows
3. **DEVELOPER_GUIDE.md** - Human-friendly onboarding
4. **docs/adr/** - Architecture Decision Records history

---

## SUMMARY: The Golden Rules

1. **Security First**: No wildcards, no error suppression, validate everything
2. **Module Boundaries**: Foundation -> Tools/Runtime -> Governance (never reverse)
3. **CLI Pattern**: Use Rule 3.1 for all CLI-based resources
4. **Local Testing**: Validate locally before touching AWS
5. **Two-Stage Build**: OCDS pattern for packaging
6. **WIF Authentication**: Never store AWS credentials
7. **State Per Environment**: Separate AWS accounts = separate states
8. **Fail Fast**: Errors must surface immediately
9. **Examples Are Production**: No shortcuts, no placeholders
10. **AWS-Managed Encryption**: Use SSE-S3 unless regulatory requirements dictate otherwise
11. **Docs Match Code**: Every code change = doc update in SAME commit
12. **Never Hardcode ARNs**: Use data sources or module outputs for ARNs, regions, account IDs

**Remember**: These rules come from real production failures identified in senior engineer review. They exist to prevent repeating those mistakes.
