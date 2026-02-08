# AI Coding Agent Rules (V2)
## Bedrock AgentCore Terraform

> Critical: This is not a typical Terraform project. These rules are mandatory.

---

## 0) Quick Start (Read This First)

**Non-negotiables**
- No IAM wildcard resources.
- No error suppression in provisioners.
- No hardcoded ARNs, regions, or account IDs.
- Validate all user inputs (ARNs, URLs, account IDs).
- Use AWS-managed encryption unless a documented regulatory exception.
- Use dynamic blocks only for repeatable blocks, never for single attributes.

**Immediate references**
- Architecture and data flows: `docs/architecture.md`
- ADRs: `docs/adr/`
- Human onboarding: `DEVELOPER_GUIDE.md`

---

## 1) Security Rules (Hard Stops)

### 1.1 IAM Resources Must Be Specific
Forbidden:
```hcl
Resource = "*"
```
Required:
```hcl
Resource = [
  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
]
Condition = {
  StringEquals = {
    "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  }
}
```

### 1.2 Errors Must Fail Fast
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

### 1.3 Dynamic Blocks Only for Collections
Forbidden:
```hcl
dynamic "kms_key_arn" { ... }
```
Required:
```hcl
kms_key_arn = var.enable_kms ? aws_kms_key.agentcore[0].arn : null
```

### 1.4 Validate All User Inputs
Required example:
```hcl
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

### 1.5 No Arbitrary Limits
Forbidden:
```bash
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}" | head -20)
```
Required:
```bash
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
```

### 1.6 Use AWS-Managed Encryption
Preferred:
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```
Use customer-managed KMS only when regulatory or cross-account needs require it.
Reference: `docs/adr/0008-aws-managed-encryption.md`

### 1.7 Never Hardcode ARNs or Regions
Forbidden:
```hcl
lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:my-function"
region     = "us-east-1"
```
Required patterns:
- Use data sources: `data.aws_caller_identity` + `data.aws_region`
- Use resource attributes: `aws_lambda_function.my_func.arn`
- Use module outputs: `module.mcp_servers.mcp_targets`
- Use existing-resource data sources: `data.aws_lambda_function.existing.arn`

---

## 2) Module Architecture (Immutable)

Dependency direction (one-way):
foundation -> tools/runtime -> governance

Never:
- foundation depends on anything
- runtime depends on governance

Module boundaries:
- foundation: Gateway, Identity, Observability
- tools: Code Interpreter, Browser
- runtime: Runtime, Memory, Packaging
- governance: Policies, Evaluations

If a resource does not fit, ask for guidance before placing it.
Reference: `docs/architecture.md`

---

## 3) Coding Rules (Terraform + Python)

### 3.1 Terraform
- Prefer `for_each` with stable keys; use `count` only when index is required.
- Use explicit types, descriptions, and validation for variables.
- Mark secrets as `sensitive = true` and avoid leaking outputs.
- Avoid `depends_on` unless implicit dependencies are insufficient.
- Avoid `null_resource` unless using the CLI pattern with hash triggers.
- Keep provider config centralized; never hardcode ARNs or regions.

### 3.2 Python
- Target Python 3.12 only.
- Format with Black and lint with Flake8 (line length 120).
- Use `pytest`; keep tests under `examples/*/agent-code/tests/`.
- Use `logging` instead of `print` for runtime behavior.
- Prefer type hints for public functions; keep modules small and cohesive.
- Avoid network calls in unit tests; mock external services.

---

## 4) CLI-Based Resources (Required Pattern)

### 4.1 Resources That Must Use CLI
1. Runtime
2. Memory
3. Policy Engine
4. Cedar Policies
5. Evaluators
6. OAuth2 Providers
7. Credential Providers

### 4.2 Mandatory Terraform Pattern
```hcl
resource "null_resource" "resource_name" {
  triggers = {
    config_hash = sha256(jsonencode(var.resource_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-X \
        --name ${var.resource_name} \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/output.json

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

### 4.3 Migration When Native Resources Appear
1. `terraform import aws_bedrockagentcore_X.main <id>`
2. Replace `null_resource` with native resource
3. Update outputs to native attributes
4. Confirm `terraform plan` shows no changes
5. Remove `.terraform/*.json`

Never skip the import step.

---

## 5) Build and Packaging (OCDS Pattern)

### 5.1 Two-Stage Build Is Required
```bash
BUILD_DIR=$(mktemp -d)
DEPS_DIR="$BUILD_DIR/deps"
pip install -t "$DEPS_DIR" -r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")

CODE_DIR="$BUILD_DIR/code"
cp -r "${local.source_path}"/* "$CODE_DIR/"

cd "$BUILD_DIR"
zip -r deployment.zip deps/ code/
```

### 5.2 Hash-Based Triggers Are Required
```hcl
triggers = {
  dependencies_hash = filemd5(local.dependencies_file)
  source_hash = sha256(join("", [
    for f in fileset(local.source_path, "**") :
    filesha256("${local.source_path}/${f}")
  ]))
}
```

---

## 6) Testing and CI (Local-First)

### 6.1 Local Validation (No AWS Required)
```bash
terraform fmt -check
terraform validate
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars
tflint
checkov
```

### 6.2 CI Stage Order Is Fixed
1. validate (fmt, validate, plan) - no AWS
2. lint (tflint, checkov) - no AWS
3. test (examples, policies) - no AWS
4. deploy-dev (auto)
5. deploy-test (manual)
6. deploy-prod (manual)

CI gate: if Terraform files change, the MR must include docs updates and tests updates.
Enforced by pre-commit hooks and the `validate:docs-and-tests` job.
GitHub Actions runs validate, TFLint, Checkov, and example checks while the repo is hosted on GitHub.

---

## 7) GitLab CI Auth (WIF Only)

- Never store AWS credentials in CI variables.
- Use OIDC WIF for all environments.

Required setup:
```yaml
before_script:
  - export AWS_ROLE_ARN=${CI_ENVIRONMENT_ROLE_ARN}
  - export AWS_WEB_IDENTITY_TOKEN_FILE=${GITLAB_TOKEN_FILE}
  - aws sts get-caller-identity
```

State is per environment, not per branch. Use separate buckets per account.

---

## 8) Documentation Sync (Mandatory)

Every code change requires a matching documentation update in the same commit.
Enforced by the `docs-sync-check` pre-commit hook and the `validate:docs-and-tests` CI job.

Minimum sync rules:
- New variable: README variables table + `terraform.tfvars.example`
- New resource: module README + `docs/architecture.md`
- Security change: update ADRs or `CLAUDE.md` anti-patterns
- New example: add README + add validation in `scripts/validate_examples.sh`

---

## 9) Discovery and Identity

- Agents must expose `/.well-known/agent-card.json`.
- Agents must register with Cloud Map or Gateway Manifest.
- Tools must be accessed via the AgentCore Gateway (no direct Lambda invoke).
- Agent-to-agent calls require workload tokens; user identity must propagate.

---

## 10) Decision Framework (Fast Lookup)

| Question | Answer |
| --- | --- |
| Terraform-native or CLI? | If `aws_bedrockagentcore_X` exists, use native. Otherwise use CLI pattern. |
| Which module? | Foundation, Tools, Runtime, Governance (no new modules). |
| Use dynamic block? | Only for repeatable blocks. |
| KMS or AWS-managed? | AWS-managed unless a documented exception. |
| Hardcode ARNs/regions? | Never; use data sources or module outputs. |

---

## 11) Versions (Pinned)

- Terraform: 1.14.4
- AWS provider: ~> 5.80
- null provider: ~> 3.2
- external provider: ~> 2.3
- Python: 3.12
- AWS CLI: >= 2.0
- Checkov: >= 3.0
- TFLint: >= 0.50

---

## 12) Full Checklist (Before Commit)

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -backend=false -var-file=examples/research-agent.tfvars
checkov -d . --framework terraform --compact
tflint --recursive
pre-commit run --all-files
```

---

## 13) Key ADRs

- 0001: 4-module architecture
- 0002: CLI-based resources
- 0003: GitLab CI with WIF
- 0004: S3 backend per environment
- 0005: Hybrid secrets management
- 0006: Separate backends (not workspaces)
- 0007: Single region
- 0008: AWS-managed encryption
