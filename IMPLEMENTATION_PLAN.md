# Comprehensive Test & Validation Plan for AWS Bedrock AgentCore Terraform

## Executive Summary

**STATUS**: Implementation has CRITICAL security issues requiring immediate remediation before ANY deployment.

**Senior Engineer Review Score**: 6.5/10 - NOT READY FOR PRODUCTION

Create a comprehensive test suite AND fix critical vulnerabilities in the AWS Bedrock AgentCore Terraform implementation (41 files, 4 modules, 9 features). Implementation has excellent architecture but contains security flaws and zero automated testing.

## SENIOR DEVOPS ENGINEER CRITICAL REVIEW

### Edge Cases & Missing Best Practices Identified

**CATEGORY A: DEPLOYMENT SAFETY (HIGH PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **No rollback testing** | Rollback.sh exists but never tested | Add `scripts/test_rollback.sh` + CI job to test rollback on dev monthly |
| **No blue/green deployment** | Prod deployments are all-or-nothing | For stateless resources, use `-target` or blue/green naming pattern |
| **PowerUserAccess is too broad** | WIF role can do anything except IAM | Create custom policy scoped to Bedrock, S3, CloudWatch, Lambda, KMS only |
| **No drift detection** | Config drift goes undetected | Add weekly CI job: `terraform plan -detailed-exitcode` → alert on diff |
| **No staged rollout** | Prod deploys 100% instantly | Add canary % for Agent runtimes before full deployment |

**CATEGORY B: VERSION MANAGEMENT (MEDIUM PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **No .terraform-version file** | Team uses different TF versions | Add `.terraform-version` with `1.5.7` for tfenv/asdf |
| **Provider constraint too loose** | `>= 5.30.0` allows breaking changes | Pin to `~> 5.30` (allows 5.30.x only) or exact in lockfile |
| **No module versioning** | Local modules have no release tags | For reuse: git tag modules (v1.0.0) and use git source URLs |
| **State file version not tracked** | TF upgrades can break state | Document current state version, test upgrades in dev first |

**CATEGORY C: DISASTER RECOVERY (MEDIUM PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **Single region** | us-east-1 outage = full outage | Document DR region (us-west-2), add ADR for single-region decision |
| **No state backup verification** | S3 versioning exists, never tested | Monthly: restore random state version, verify `terraform plan` works |
| **No cross-account state access** | Prod state only in prod account | Consider read-only cross-account access for auditing |
| **No runbooks** | Incident response undefined | Create `docs/runbooks/` with common failure scenarios |

**CATEGORY D: OBSERVABILITY GAPS (MEDIUM PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **Alert fatigue risk** | Many alarms, no prioritization | Tier alarms: P1 (page), P2 (ticket), P3 (log only) |
| **No SLA definitions** | Uptime expectations unclear | Define SLOs: 99.9% uptime, <500ms p99 latency |
| **No log aggregation** | Logs scattered across CloudWatch groups | Add centralized log group or export to S3/OpenSearch |
| **No dashboard** | No visual overview | Create CloudWatch dashboard with key metrics |

**CATEGORY E: SECURITY HARDENING (MEDIUM PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **KMS key policy uses kms:*** | Overly permissive key access | Scope to specific actions: Encrypt, Decrypt, GenerateDataKey |
| **No secrets rotation** | Static secrets in Secrets Manager | Enable automatic rotation for OAuth credentials |
| **No pipeline failure notifications** | CI breaks silently | Add Slack/email webhook on pipeline failure |
| **Service quotas not checked** | Could hit Lambda/S3/Bedrock limits | Pre-flight check: `aws service-quotas get-service-quota` |

**CATEGORY F: MISSING DOCUMENTATION (LOW PRIORITY)**

| Issue | Risk | Recommendation |
|-------|------|----------------|
| **No network topology diagram** | Architecture unclear visually | Add Mermaid/draw.io diagram to architecture.md |
| **No explicit workspace decision** | Confusion about multi-env approach | ADR: "Why separate backends, not workspaces" |
| **No compliance mapping** | SOC2/HIPAA requirements unknown | If applicable, map controls to Terraform resources |
| **No on-call rotation** | Who responds to alerts? | Document escalation path in RUNBOOK.md |

---

### Additional SEC Issues Not in Phase 0

| ID | Location | Issue | Fix |
|----|----------|-------|-----|
| SEC-007 | `gateway.tf:17-18` | KMS key policy uses `"kms:*"` | Replace with specific actions |
| SEC-008 | `.gitlab-ci.yml:196` | `PowerUserAccess` too broad | Create scoped IAM policy |
| SEC-009 | All modules | No `sensitive = true` on outputs | Mark ARNs/secrets as sensitive |
| SEC-010 | `packaging.tf` | No checksums for pip packages | Add `--require-hashes` to pip install |

---

### Edge Cases to Test

1. **What if Lambda ARN doesn't exist?** → Gateway creation fails, but no helpful error message
2. **What if S3 bucket already exists?** → Terraform fails, needs import or name change
3. **What if KMS key is deleted externally?** → All encrypted resources fail to decrypt
4. **What if agent source path is empty?** → Packaging creates empty zip silently
5. **What if DynamoDB lock table is full?** → State operations hang indefinitely
6. **What if Cedar policy has runtime error?** → Policy engine crashes, blocks all requests
7. **What if pip install times out?** → Packaging fails but error suppressed (SEC-003)
8. **What if WIF token expires mid-deploy?** → Partial state, requires manual cleanup

---

### Recommended Phase 0 Additions

Based on this review, add to Phase 0:

```markdown
- [ ] SEC-007: Scope KMS key policy to specific actions - 30 minutes
- [ ] SEC-008: Create scoped IAM policy for WIF (replace PowerUserAccess) - 1 hour
- [ ] SEC-009: Add `sensitive = true` to all ARN/secret outputs - 30 minutes
- [ ] Add `.terraform-version` file with `1.5.7` - 5 minutes
- [ ] Pin AWS provider to `~> 5.30` in versions.tf - 5 minutes
```

**Updated Total Time**: ~10 hours (was 8 hours)

---

## PHASE 0: CRITICAL FIXES (MUST COMPLETE BEFORE ANY OTHER WORK)

**⚠️ DEPLOYMENT BLOCKERS - Fix Immediately (1-2 days)**

Senior engineer review identified **5 CRITICAL issues** that make current code UNSAFE for deployment:

### 1. IAM Wildcard Resources (SEC-001) - 2 hours
**Location**: `modules/agentcore-foundation/iam.tf:46, 54, 94`
**Issue**: Multiple policies using `Resource = "*"` violates least privilege

**Fix Required**:
```hcl
# BEFORE (INSECURE):
Resource = "*"

# AFTER (SECURE):
Resource = [
  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
]
Condition = {
  StringEquals = {
    "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  }
}
```

### 2. Dynamic Block Syntax Error (SEC-006) - 15 minutes
**Location**: `modules/agentcore-foundation/gateway.tf:77-82`
**Issue**: Invalid `dynamic "kms_key_arn"` will cause validation failure

**Fix Required**:
```hcl
# BEFORE (BROKEN):
dynamic "kms_key_arn" {
  for_each = var.enable_kms ? [aws_kms_key.agentcore[0].arn] : []
  content {
    value = kms_key_arn.value
  }
}

# AFTER (CORRECT):
kms_key_arn = var.enable_kms ? aws_kms_key.agentcore[0].arn : null
```

### 3. Error Suppression (SEC-003) - 4 hours
**Location**: `modules/agentcore-runtime/packaging.tf:96, runtime.tf:34`
**Issue**: Using `|| true` and `2>/dev/null` masks deployment failures

**Fix Required**:
```bash
# BEFORE (MASKS ERRORS):
cp -r "${local.source_path}"/* "$BUILD_DIR/code/" 2>/dev/null || true

# AFTER (FAILS PROPERLY):
if [ ! -d "${local.source_path}" ]; then
  echo "ERROR: Source path not found: ${local.source_path}"
  exit 1
fi
cp -r "${local.source_path}"/* "$BUILD_DIR/code/"
```

### 4. Placeholder ARN Validation (SEC-002) - 1 hour
**Location**: `examples/support-agent.tfvars:22`
**Issue**: Example uses `123456789012` placeholder account

**Fix Required**:
```hcl
# Add to variables.tf
variable "mcp_targets" {
  validation {
    condition = alltrue([
      for k, v in var.mcp_targets :
      !can(regex("123456789012", v.lambda_arn))
    ])
    error_message = "Placeholder ARNs detected. Replace 123456789012 with actual account ID."
  }
}
```

### 5. Packaging Dependency Limit (SEC-004) - 30 minutes
**Location**: `modules/agentcore-runtime/packaging.tf:57`
**Issue**: `head -20` limits dependencies to 20 packages

**Fix Required**:
```bash
# BEFORE (LIMITS TO 20):
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}" | head -20)

# AFTER (ALL DEPENDENCIES):
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
```

**Total Time to Fix**: ~8 hours
**Priority**: MUST complete before proceeding with testing

---

## Current State Analysis

### What Exists (With Issues)
- ⚠️ **4 complete modules** - contain CRITICAL security flaws
- ⚠️ **35 Terraform files** - 3 have syntax errors
- ✅ **6 documentation files** - excellent quality (9/10)
- ⚠️ **2 working examples** - contain placeholder ARNs
- ✅ **2 Cedar policies** - valid syntax, no validation
- ✅ **Makefile** - basic targets, needs expansion

**Senior Engineer Assessment**: 11/25 items complete (44% production-ready)

### What's Missing (Critical Gaps)
- ❌ **No automated tests** - zero test files exist
- ❌ **No CI/CD pipeline** - no GitLab/GitHub configuration
- ❌ **No security scanning** - Checkov/TFLint not integrated
- ❌ **No example validation** - examples not tested
- ❌ **No Cedar validation** - policies not checked
- ❌ **No pre-commit hooks** - no local enforcement
- ❌ **No promotion strategy** - dev/test/prod undefined

## GitLab CI/CD Configuration (On-Prem)

### Pipeline Structure

```yaml
# .gitlab-ci.yml
image: amazon/aws-cli:latest

stages:
  - fix          # Apply critical fixes (temporary stage)
  - validate     # fmt, validate, plan (NO AWS resources)
  - lint         # TFLint, Checkov (NO AWS resources)
  - test         # Cedar validation, examples (NO AWS resources)
  - deploy-dev   # Auto-deploy to dev AWS account
  - deploy-test  # Manual approval → test AWS account
  - deploy-prod  # Manual approval → prod AWS account

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/terraform
  AWS_DEFAULT_REGION: us-east-1
  # State per environment
  TF_STATE_BUCKET_DEV: terraform-state-dev-${CI_PROJECT_ID}
  TF_STATE_BUCKET_TEST: terraform-state-test-${CI_PROJECT_ID}
  TF_STATE_BUCKET_PROD: terraform-state-prod-${CI_PROJECT_ID}

# AWS Web Identity Federation (WIF) from GitLab Groups
before_script:
  - apk add --no-cache terraform tflint
  - export AWS_ROLE_ARN=${!CI_ENVIRONMENT_ROLE_ARN}  # Per environment
  - export AWS_WEB_IDENTITY_TOKEN_FILE=${GITLAB_TOKEN_FILE}
  - aws sts get-caller-identity  # Verify WIF works
```

### WIF Setup Instructions

```bash
# 1. Create OIDC Provider in each AWS Account (dev, test, prod)
aws iam create-open-id-connect-provider \
  --url https://gitlab.yourcompany.com \
  --client-id-list "https://gitlab.yourcompany.com" \
  --thumbprint-list "<gitlab-cert-thumbprint>"

# 2. Create IAM Role for GitLab (per environment)
aws iam create-role \
  --role-name gitlab-terraform-deployer-dev \
  --assume-role-policy-document file://trust-policy.json

# trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/gitlab.yourcompany.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "gitlab.yourcompany.com:sub": "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:main"
      }
    }
  }]
}

# 3. Attach SCOPED policy to role (NOT PowerUserAccess - see SEC-008)
# Create custom policy first:
cat > gitlab-terraform-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAgentCore",
      "Effect": "Allow",
      "Action": ["bedrock:*", "bedrock-agent:*", "bedrock-agentcore:*"],
      "Resource": "*"
    },
    {
      "Sid": "S3StateAndArtifacts",
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::terraform-state-*",
        "arn:aws:s3:::terraform-state-*/*",
        "arn:aws:s3:::agentcore-*",
        "arn:aws:s3:::agentcore-*/*"
      ]
    },
    {
      "Sid": "DynamoDBLocking",
      "Effect": "Allow",
      "Action": ["dynamodb:*"],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
    },
    {
      "Sid": "CloudWatch",
      "Effect": "Allow",
      "Action": ["logs:*", "cloudwatch:*", "xray:*"],
      "Resource": "*"
    },
    {
      "Sid": "KMS",
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateKey", "kms:CreateAlias"],
      "Resource": "*"
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": ["lambda:*"],
      "Resource": "arn:aws:lambda:*:*:function:*-mcp"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": ["iam:PassRole", "iam:GetRole", "iam:CreateRole", "iam:AttachRolePolicy"],
      "Resource": "arn:aws:iam::*:role/agentcore-*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name gitlab-terraform-agentcore-policy \
  --policy-document file://gitlab-terraform-policy.json

aws iam attach-role-policy \
  --role-name gitlab-terraform-deployer-dev \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/gitlab-terraform-agentcore-policy

# 4. Configure GitLab CI/CD Variables (per environment group)
# Settings → CI/CD → Variables:
# - CI_ENVIRONMENT_ROLE_ARN_DEV: arn:aws:iam::111111111111:role/gitlab-terraform-deployer-dev
# - CI_ENVIRONMENT_ROLE_ARN_TEST: arn:aws:iam::222222222222:role/gitlab-terraform-deployer-test
# - CI_ENVIRONMENT_ROLE_ARN_PROD: arn:aws:iam::333333333333:role/gitlab-terraform-deployer-prod
```

---

## Promotion Strategy (Branch + Tag Based)

### Branch Structure

```
Repository Branches:
├── main              → Dev environment (auto-deploy on merge)
├── release/v1.x      → Test environment (manual approval)
└── tags: v1.x.x      → Prod environment (manual approval + audit)

Workflow:
1. Feature → MR to main → Auto-deploy to DEV
2. main → release/v1.2 branch → Manual deploy to TEST
3. Tag v1.2.3 on release → Manual deploy to PROD
```

### State Management (S3 Backend with Locking)

```hcl
# backend-dev.tf (generated per environment)
terraform {
  backend "s3" {
    bucket         = "terraform-state-dev-12345"
    key            = "agentcore/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-dev"  # S3 locking uses DynamoDB

    # S3 Bucket Versioning provides backup/rollback
    versioning     = true
  }
}
```

**Note**: S3 backend automatically handles state locking via DynamoDB table. Must create table first:

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock-dev \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Secrets Management Strategy

**Recommendation: GitLab CI/CD Variables + AWS Secrets Manager Hybrid**

```
Level 1: GitLab CI/CD Variables (per environment group)
├── AWS_ROLE_ARN_DEV/TEST/PROD       # WIF role ARNs
├── TF_STATE_BUCKET_DEV/TEST/PROD    # State buckets
├── TF_VAR_region                     # AWS region
└── TF_VAR_environment                # dev/test/prod

Level 2: AWS Secrets Manager (runtime secrets)
├── agentcore/dev/mcp-lambda-arns     # Lambda ARNs per environment
├── agentcore/dev/oauth-credentials   # OAuth tokens
├── agentcore/dev/api-keys            # External API keys
└── agentcore/dev/gateway-config      # MCP target configurations

Reference in Terraform:
data "aws_secretsmanager_secret_version" "mcp_config" {
  secret_id = "agentcore/${var.environment}/mcp-lambda-arns"
}

locals {
  mcp_targets = jsondecode(data.aws_secretsmanager_secret_version.mcp_config.secret_string)
}
```

---

## Three Example Agents (Production-Ready)

### Example 1: Hello World S3 Explorer

**Location**: `terraform/examples/1-hello-world/`

**Purpose**: Minimal agent demonstrating S3 listing capability

```python
# examples/1-hello-world/agent-code/runtime.py
import boto3
import json

def handler(event, context):
    """
    Simple agent that lists S3 buckets and returns summary.
    Demonstrates: Basic runtime, AWS SDK usage, structured output.
    """
    s3 = boto3.client('s3')

    # List buckets
    buckets = s3.list_buckets()

    result = {
        "status": "success",
        "message": "Hello from Bedrock AgentCore!",
        "bucket_count": len(buckets['Buckets']),
        "buckets": [b['Name'] for b in buckets['Buckets'][:5]],  # First 5
        "timestamp": buckets['ResponseMetadata']['HTTPHeaders']['date']
    }

    return result

if __name__ == "__main__":
    print(json.dumps(handler({}, None), indent=2))
```

**Terraform Config**:
```hcl
# examples/1-hello-world/terraform.tfvars
agent_name          = "hello-world-s3"
region              = "us-east-1"
environment         = "dev"

# Minimal features
enable_gateway          = false
enable_code_interpreter = false
enable_browser          = false
enable_identity         = false
enable_policy_engine    = false
enable_evaluations      = false

# Just runtime + memory
enable_runtime      = true
runtime_source_path = "./examples/1-hello-world/agent-code"
runtime_entry_file  = "runtime.py"

enable_memory = false  # Not needed for hello world

# Observability
enable_observability = true
enable_kms           = true
```

---

### Example 2: Gateway Tool - Titanic Data Analysis

**Location**: `terraform/examples/2-gateway-tool/`

**Purpose**: Demonstrates MCP gateway with code interpreter analyzing Titanic dataset

**Components**:
1. **Agent Code**: Orchestrates data analysis
2. **MCP Lambda**: Provides Titanic dataset via MCP protocol
3. **Code Interpreter**: Performs pandas analysis

```python
# examples/2-gateway-tool/agent-code/runtime.py
import json

def handler(event, context):
    """
    Agent that:
    1. Fetches Titanic dataset via MCP tool
    2. Uses code interpreter to analyze survival rates
    3. Returns insights
    """
    # Invoke MCP tool to get dataset
    mcp_request = {
        "tool": "titanic-dataset",
        "action": "fetch",
        "format": "csv"
    }

    # Agent would invoke gateway here
    # dataset = invoke_mcp_tool(mcp_request)

    # Code interpreter would analyze
    analysis_code = """
import pandas as pd
import json

# Load dataset
df = pd.read_csv('titanic.csv')

# Calculate survival statistics
survival_by_class = df.groupby('Pclass')['Survived'].mean()
survival_by_gender = df.groupby('Sex')['Survived'].mean()

results = {
    "total_passengers": len(df),
    "survival_rate": df['Survived'].mean(),
    "survival_by_class": survival_by_class.to_dict(),
    "survival_by_gender": survival_by_gender.to_dict()
}

print(json.dumps(results))
"""

    # Return analysis
    return {
        "status": "success",
        "analysis": "Titanic survival analysis complete",
        "insights": {
            "total_passengers": 891,
            "overall_survival_rate": 0.38,
            "first_class_survival": 0.63,
            "third_class_survival": 0.24,
            "female_survival": 0.74,
            "male_survival": 0.19
        }
    }
```

**MCP Lambda Tool**:
```python
# examples/2-gateway-tool/lambda/titanic-mcp/index.py
import json
import urllib.request

TITANIC_URL = "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv"

def lambda_handler(event, context):
    """
    MCP tool that provides Titanic dataset.
    Demonstrates: Lambda-based MCP target, data retrieval.
    """
    action = event.get('action', 'fetch')

    if action == 'fetch':
        # Download Titanic dataset
        with urllib.request.urlopen(TITANIC_URL) as response:
            data = response.read().decode('utf-8')

        return {
            'statusCode': 200,
            'body': json.dumps({
                'dataset': 'titanic',
                'format': 'csv',
                'rows': len(data.split('\n')) - 1,
                'data': data[:1000]  # First 1000 chars for demo
            })
        }

    elif action == 'schema':
        return {
            'statusCode': 200,
            'body': json.dumps({
                'columns': ['PassengerId', 'Survived', 'Pclass', 'Name', 'Sex', 'Age', 'SibSp', 'Parch', 'Fare', 'Embarked'],
                'types': ['int', 'int', 'int', 'str', 'str', 'float', 'int', 'int', 'float', 'str']
            })
        }
```

**Terraform Config**:
```hcl
# examples/2-gateway-tool/terraform.tfvars
agent_name          = "titanic-analyzer"
region              = "us-east-1"
environment         = "dev"

# Enable gateway and code interpreter
enable_gateway          = true
enable_code_interpreter = true
code_interpreter_network_mode = "SANDBOX"

# MCP target (Lambda deployed separately)
mcp_targets = {
  titanic_dataset = {
    name        = "titanic-dataset-tool"
    lambda_arn  = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:titanic-mcp"
    description = "Provides Titanic dataset for analysis"
  }
}

# Runtime
enable_runtime      = true
runtime_source_path = "./examples/2-gateway-tool/agent-code"

# Observability
enable_observability = true
enable_kms           = true
```

---

### Example 3: Deep Research Agent (Full-Featured)

**Location**: `terraform/examples/3-deepresearch/`

**Purpose**: Complete agent copied from `deepagents-bedrock-agentcore-terraform/deepresearch`

```bash
# Copy deep research agent into examples
cp -r deepagents-bedrock-agentcore-terraform/deepresearch/ \
      terraform/examples/3-deepresearch/agent-code/
```

**Terraform Config**:
```hcl
# examples/3-deepresearch/terraform.tfvars
agent_name          = "deep-research"
region              = "us-east-1"
environment         = "prod"

# Full feature set
enable_gateway          = true
enable_code_interpreter = true
enable_browser          = true
enable_identity         = false  # Add if needed
enable_observability    = true
enable_kms              = true

# Gateway with research tools
mcp_targets = {
  arxiv = {
    name        = "arxiv-search"
    lambda_arn  = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:arxiv-mcp"
    description = "ArXiv paper search"
  }
  pubmed = {
    name        = "pubmed-search"
    lambda_arn  = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:pubmed-mcp"
    description = "PubMed literature search"
  }
}

# Runtime with dependencies
enable_runtime      = true
runtime_source_path = "./examples/3-deepresearch/agent-code"
runtime_entry_file  = "runtime.py"

enable_memory = true
memory_type   = "BOTH"

# Code analysis
enable_code_interpreter = true
code_interpreter_network_mode = "SANDBOX"

# Web research
enable_browser = true
browser_network_mode = "SANDBOX"

# Governance
enable_evaluations = true
evaluation_type    = "REASONING"
evaluator_model_id = "anthropic.claude-sonnet-4-5"
```

---

## Test Architecture (Maximum Local Testing - No AWS Required)

### Test Framework Selection

```
Testing Tools Stack (LOCAL FIRST):
├── Level 1: Local (NO AWS)
│   ├── terraform fmt -check       # Style (instant)
│   ├── terraform validate         # Syntax (5 sec)
│   ├── terraform plan -backend=false  # Logic (30 sec)
│   ├── TFLint                     # Best practices (10 sec)
│   ├── Checkov                    # Security scan (20 sec)
│   └── Cedar CLI                  # Policy validation (5 sec)
│   → TOTAL: ~70 seconds, $0 cost
│
├── Level 2: CI Pipeline (NO AWS)
│   ├── All Level 1 tests
│   ├── Multiple example validation
│   ├── Documentation link checking
│   └── Pre-commit hook verification
│   → TOTAL: ~3 minutes, $0 cost
│
├── Level 3: Dev Deployment (AWS Dev Account)
│   ├── terraform apply (dev only)
│   ├── Output validation
│   └── Smoke tests
│   → TOTAL: ~10 minutes, ~$5/day cost
│
└── Level 4: Integration (AWS Test Account)
    ├── Full deployment test
    ├── End-to-end validation
    └── Manual QA
    → TOTAL: ~30 minutes, ~$20/test cost
```

**Key Principle**: Developer can validate 100% locally before pushing. No AWS account needed for development.

### Test Structure

```
terraform/
├── tests/
│   ├── unit/                   # Module-level tests
│   │   ├── foundation_test.go
│   │   ├── tools_test.go
│   │   ├── runtime_test.go
│   │   └── governance_test.go
│   │
│   ├── integration/            # Module composition tests
│   │   ├── minimal_agent_test.go
│   │   ├── full_agent_test.go
│   │   └── secure_prod_test.go
│   │
│   ├── examples/               # Example validation
│   │   ├── research_agent_test.go
│   │   └── support_agent_test.go
│   │
│   ├── security/               # Security validation
│   │   ├── checkov_test.sh
│   │   ├── tflint_test.sh
│   │   └── policy_test.sh
│   │
│   ├── validation/             # Output & behavior tests
│   │   ├── outputs_test.sh
│   │   ├── cedar_syntax_test.sh
│   │   └── packaging_test.sh
│   │
│   ├── fixtures/               # Test data
│   │   ├── minimal/
│   │   ├── complete/
│   │   └── secure/
│   │
│   └── helpers/                # Test utilities
│       ├── terraform_helpers.go
│       ├── aws_helpers.go
│       └── assertions.go
│
├── .github/
│   └── workflows/
│       ├── test.yml            # CI/CD pipeline
│       ├── security.yml        # Security scans
│       └── docs.yml            # Documentation checks
│
└── scripts/
    ├── test_all.sh             # Run all tests
    ├── test_unit.sh            # Unit tests only
    ├── test_integration.sh     # Integration tests
    └── validate_examples.sh    # Example validation
```

## Test Plan by Category

### 1. Terraform Native Validation Tests

**Location**: `tests/validation/`

**Tests to Implement**:

```bash
# tests/validation/terraform_native_test.sh
#!/bin/bash
set -e

echo "Running Terraform native validation tests..."

# Test 1: Syntax validation for all modules
test_syntax_validation() {
    for module in foundation tools runtime governance; do
        echo "Validating module: agentcore-$module"
        cd modules/agentcore-$module
        terraform init -backend=false
        terraform validate
        cd ../../
    done
}

# Test 2: Format checking
test_format_check() {
    if ! terraform fmt -check -recursive; then
        echo "ERROR: Terraform files not properly formatted"
        exit 1
    fi
}

# Test 3: Plan generation (dry run)
test_plan_generation() {
    terraform init -backend=false
    terraform plan -var-file="examples/research-agent.tfvars" -out=test.tfplan
    rm test.tfplan
}

# Run all tests
test_syntax_validation
test_format_check
test_plan_generation

echo "✅ All Terraform native tests passed"
```

**Expected Results**:
- All modules validate without errors
- All files pass format check
- Plans generate successfully

---

### 2. Security Scanning Tests

**Location**: `tests/security/`

**Tests to Implement**:

```bash
# tests/security/checkov_scan.sh
#!/bin/bash

echo "Running Checkov security scan..."

checkov -d . \
  --framework terraform \
  --quiet \
  --compact \
  --output cli \
  --output json:checkov_results.json

# Check for high/critical severity issues
CRITICAL=$(jq '.summary.failed' checkov_results.json)
if [ "$CRITICAL" -gt 0 ]; then
    echo "❌ Found $CRITICAL security issues"
    jq '.results.failed_checks' checkov_results.json
    exit 1
fi

echo "✅ No critical security issues found"
```

```bash
# tests/security/tflint_scan.sh
#!/bin/bash

echo "Running TFLint..."

tflint --init
tflint --recursive --format compact

echo "✅ TFLint checks passed"
```

**Expected Results**:
- No critical or high severity security issues
- No TFLint rule violations
- All resources follow AWS best practices

---

### 3. Unit Tests (Terratest)

**Location**: `tests/unit/`

**Test Example**:

```go
// tests/unit/foundation_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestFoundationModuleGateway(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../../modules/agentcore-foundation",
        Vars: map[string]interface{}{
            "agent_name":        "test-agent",
            "region":            "us-east-1",
            "environment":       "test",
            "enable_gateway":    true,
            "enable_observability": true,
            "enable_kms":        true,
        },
        NoColor: true,
    })

    defer terraform.Destroy(t, terraformOptions)

    // Test 1: Module initializes
    terraform.Init(t, terraformOptions)

    // Test 2: Plan succeeds
    terraform.Plan(t, terraformOptions)

    // Test 3: Apply succeeds
    terraform.Apply(t, terraformOptions)

    // Test 4: Outputs are correct
    gatewayID := terraform.Output(t, terraformOptions, "gateway_id")
    assert.NotEmpty(t, gatewayID)

    kmsKeyID := terraform.Output(t, terraformOptions, "kms_key_id")
    assert.NotEmpty(t, kmsKeyID)
}

func TestFoundationModuleWithoutGateway(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../../modules/agentcore-foundation",
        Vars: map[string]interface{}{
            "agent_name":     "test-agent",
            "region":         "us-east-1",
            "environment":    "test",
            "enable_gateway": false, // Disabled
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Gateway should not be created
    gatewayID := terraform.Output(t, terraformOptions, "gateway_id")
    assert.Empty(t, gatewayID)
}
```

**Tests for Each Module**:
- `foundation_test.go`: Gateway, Identity, Observability
- `tools_test.go`: Code Interpreter, Browser
- `runtime_test.go`: Runtime, Memory, Packaging
- `governance_test.go`: Policy, Evaluations

**Test Coverage**:
- ✅ Module initializes
- ✅ Plan succeeds
- ✅ Apply succeeds (dry-run in CI)
- ✅ Outputs are valid
- ✅ Conditional resources (enable/disable features)
- ✅ Variable validation
- ✅ IAM role creation
- ✅ Dependencies work correctly

---

### 4. Integration Tests

**Location**: `tests/integration/`

**Test Example**:

```go
// tests/integration/minimal_agent_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestMinimalAgentDeployment(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../../",
        VarFiles: []string{"tests/fixtures/minimal/terraform.tfvars"},
        NoColor: true,
    }

    defer terraform.Destroy(t, terraformOptions)

    // Initialize
    terraform.Init(t, terraformOptions)

    // Plan
    planOutput := terraform.Plan(t, terraformOptions)
    assert.Contains(t, planOutput, "Plan:")

    // Apply
    terraform.Apply(t, terraformOptions)

    // Verify outputs
    agentSummary := terraform.OutputMap(t, terraformOptions, "agent_summary")
    assert.Equal(t, "minimal-agent", agentSummary["name"])
    assert.Equal(t, "true", agentSummary["gateway_enabled"])
}
```

**Integration Test Scenarios**:
1. **Minimal Agent** (gateway only)
2. **Full-Featured Agent** (all features enabled)
3. **Secure Production** (VPC, KMS, policies)
4. **Research Agent Example** (from examples/)
5. **Support Agent Example** (from examples/)

---

### 5. Example Validation Tests

**Location**: `tests/examples/`

**Test Script**:

```bash
# scripts/validate_examples.sh
#!/bin/bash
set -e

echo "Validating example configurations..."

validate_example() {
    local example_file=$1
    echo "Testing: $example_file"

    # Initialize with example vars
    terraform init -backend=false

    # Validate syntax
    terraform validate

    # Generate plan (no apply)
    terraform plan -var-file="$example_file" -out=test.tfplan

    # Check plan for errors
    if [ $? -ne 0 ]; then
        echo "❌ Plan failed for $example_file"
        return 1
    fi

    # Cleanup
    rm -f test.tfplan

    echo "✅ $example_file validated"
}

# Test each example
validate_example "examples/research-agent.tfvars"
validate_example "examples/support-agent.tfvars"

echo "✅ All examples validated successfully"
```

---

### 6. Cedar Policy Validation

**Location**: `tests/validation/`

**Test Script**:

```bash
# tests/validation/cedar_syntax_test.sh
#!/bin/bash
set -e

echo "Validating Cedar policies..."

# Install Cedar CLI if not present
if ! command -v cedar &> /dev/null; then
    echo "Installing Cedar CLI..."
    cargo install cedar-policy-cli
fi

# Test each Cedar policy
for policy in modules/agentcore-governance/cedar_policies/*.cedar; do
    echo "Validating: $policy"

    # Syntax check
    cedar validate --policies "$policy"

    # Schema validation (if schema exists)
    if [ -f "modules/agentcore-governance/cedar_policies/schema.json" ]; then
        cedar validate --policies "$policy" \
                      --schema "modules/agentcore-governance/cedar_policies/schema.json"
    fi

    echo "✅ $policy is valid"
done

echo "✅ All Cedar policies validated"
```

---

### 7. Output Verification Tests

**Location**: `tests/validation/`

**Test Script**:

```bash
# tests/validation/outputs_test.sh
#!/bin/bash
set -e

echo "Verifying Terraform outputs..."

# Initialize and plan
terraform init -backend=false
terraform plan -var-file="examples/research-agent.tfvars" -out=test.tfplan

# Apply (dry-run only in CI)
# terraform apply test.tfplan

# Verify output structure
terraform output -json > outputs.json

# Test 1: Gateway outputs
jq -e '.gateway_id' outputs.json
jq -e '.gateway_arn' outputs.json
jq -e '.gateway_endpoint' outputs.json

# Test 2: Runtime outputs
jq -e '.deployment_bucket_name' outputs.json
jq -e '.runtime_role_arn' outputs.json

# Test 3: Summary output
jq -e '.agent_summary' outputs.json

echo "✅ All outputs present and valid"

# Cleanup
rm -f test.tfplan outputs.json
```

---

### 8. Packaging Tests

**Location**: `tests/validation/`

**Test Script**:

```bash
# tests/validation/packaging_test.sh
#!/bin/bash
set -e

echo "Testing two-stage packaging process..."

# Create test agent directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/test-agent"
cd "$TEST_DIR/test-agent"

# Create test files
cat > runtime.py << 'EOF'
def main():
    return {"status": "success"}
EOF

cat > pyproject.toml << 'EOF'
[project]
name = "test-agent"
version = "1.0.0"
dependencies = ["requests>=2.28.0"]
EOF

# Test hash calculation
cd ../../terraform
terraform init -backend=false

# Set variables pointing to test agent
export TF_VAR_runtime_source_path="$TEST_DIR/test-agent"
export TF_VAR_agent_name="test-agent"
export TF_VAR_enable_packaging=true

# Generate plan to trigger packaging
terraform plan -target=module.agentcore_runtime

echo "✅ Packaging process validated"
```

---

### 9. CI/CD Pipeline

**Location**: `.github/workflows/`

**GitHub Actions Workflow**:

```yaml
# .github/workflows/test.yml
name: Terraform Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  validate:
    name: Terraform Validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate

  security:
    name: Security Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform
          quiet: true
          soft_fail: false

      - name: Run TFLint
        uses: terraform-linters/setup-tflint@v2
      - run: tflint --init
      - run: tflint --recursive

  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.20'

      - name: Install Terratest
        run: go get github.com/gruntwork-io/terratest/modules/terraform

      - name: Run Unit Tests
        run: |
          cd tests/unit
          go test -v -timeout 30m

  example-validation:
    name: Validate Examples
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Validate Examples
        run: bash scripts/validate_examples.sh

  cedar-policies:
    name: Cedar Policy Validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable

      - name: Install Cedar CLI
        run: cargo install cedar-policy-cli

      - name: Validate Cedar Policies
        run: bash tests/validation/cedar_syntax_test.sh
```

---

## Pre-Commit Hooks (GitHub During Development)

Since repo will be on GitHub initially, set up pre-commit hooks for local enforcement:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_checkov
        args:
          - --args=--quiet

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-added-large-files
        args: ['--maxkb=1000']

# Install: pip install pre-commit
# Setup: pre-commit install
# Run: pre-commit run --all-files
```

**Developer Setup**:
```bash
# One-time setup
pip install pre-commit
cd terraform
pre-commit install

# Now runs automatically on git commit
git add .
git commit -m "feat: add gateway module"
# ← Pre-commit hooks run here, block commit if failures
```

---

## Implementation Phases (REVISED with Critical Fixes First)

### Phase 0: CRITICAL FIXES + DOCS (Days 1-2) ⚠️ BLOCKING
**Priority**: CRITICAL
**Effort**: 1-2 days
**Cost**: $0 (no deployment)

**MUST complete before any other work**

**Rule: Every code fix MUST have corresponding doc update in SAME commit**

Tasks (Code + Docs Together):
- [ ] Fix IAM wildcard resources (SEC-001) - 2 hours
      → Update CLAUDE.md anti-patterns with specific fix
- [ ] Fix dynamic block syntax (SEC-006) - 15 minutes
      → Update CLAUDE.md Rule 1.3 with confirmed fix
- [ ] Remove error suppression (SEC-003) - 4 hours
      → Update CLAUDE.md Rule 1.2 with examples from fixed code
- [ ] Add placeholder ARN validation (SEC-002) - 1 hour
      → Update CLAUDE.md Rule 1.4 + README variables section
- [ ] Fix packaging dependency limit (SEC-004) - 30 minutes
      → Update CLAUDE.md Rule 1.5 with fix
- [ ] Add KMS key policy conditions - 2 hours
      → Update architecture.md security section
- [ ] Remove timestamp() from tags - 15 minutes
      → Update CLAUDE.md anti-patterns
- [ ] Create initial documentation reflecting CURRENT state - 2 hours
      → README.md (matching deepresearch quality)
      → architecture.md (current state WITH issues noted)
      → CLAUDE.md (rules derived from findings)
      → DEVELOPER_GUIDE.md (team onboarding)

Deliverables (Code):
- Fixed `modules/agentcore-foundation/iam.tf`
- Fixed `modules/agentcore-foundation/gateway.tf`
- Fixed `modules/agentcore-runtime/packaging.tf`
- Fixed `modules/agentcore-runtime/runtime.tf`
- Updated `variables.tf` with ARN validation

Deliverables (Docs - MUST accompany code):
- `CLAUDE.md` - Rules/principles for AI agents (at project root)
- `DEVELOPER_GUIDE.md` - Team onboarding (at project root)
- `README.md` - User-facing docs matching deepresearch quality
- `docs/architecture.md` - System architecture (current + planned)
- `docs/adr/0001-0005` - Architecture Decision Records

Commit Strategy:
```bash
# Each fix is ONE commit with code + docs:
git add modules/agentcore-foundation/gateway.tf CLAUDE.md
git commit -m "fix(SEC-006): replace dynamic block with direct attribute

- Fixed kms_key_arn dynamic block syntax error at gateway.tf:77-82
- Updated CLAUDE.md Rule 1.3 with confirmed fix pattern

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

Verification:
```bash
terraform validate           # Must pass
terraform plan -backend=false  # Must succeed
checkov -d .                 # Zero critical/high issues
# Verify docs match code:
git diff --name-only | grep -E '\.(tf)$' && \
git diff --name-only | grep -E '\.(md)$' || exit 1
```

---

### Phase 1: Local Testing + Documentation (Days 3-5)
**Priority**: High
**Effort**: 2-3 days
**Cost**: $0 (all local)

Tasks:
- [ ] Create test directory structure
- [ ] **Create ADR folder and architecture docs**
- [ ] **Generate claude.md (development guide for Claude)**
- [ ] **Create architecture.md (system architecture)**
- [ ] **Create DEVELOPER_GUIDE.md (team guide)**
- [ ] Implement terraform fmt/validate script
- [ ] Set up TFLint configuration
- [ ] Set up Checkov scanning
- [ ] Create Makefile test targets
- [ ] Set up pre-commit hooks
- [ ] Add Cedar CLI validation

Deliverables:
- **`docs/adr/` folder** (Architecture Decision Records)
  - `docs/adr/0001-module-structure.md`
  - `docs/adr/0002-cli-based-resources.md`
  - `docs/adr/0003-gitlab-ci-pipeline.md`
  - `docs/adr/0004-state-management.md`
  - `docs/adr/0005-secrets-strategy.md`
  - `docs/adr/0006-separate-backends-not-workspaces.md` *(NEW - from DevOps review)*
  - `docs/adr/0007-single-region-decision.md` *(NEW - from DevOps review)*
  - `docs/adr/0008-aws-managed-encryption.md` *(NEW - simplicity over KMS)*
  - `docs/adr/0009-agent-discovery-identity.md` *(PROPOSED - pre-ADR based on RULE 9 & 10)*
- **`CLAUDE.md`** (Claude AI development guide)
- **`docs/architecture.md`** (System architecture + network topology diagram)
- **`docs/runbooks/`** *(NEW - from DevOps review)*
  - `docs/runbooks/state-recovery.md`
  - `docs/runbooks/rollback-procedure.md`
  - `docs/runbooks/common-failures.md`
- **`DEVELOPER_GUIDE.md`** (Developer onboarding)
- **`.terraform-version`** with `1.5.7` *(NEW - from DevOps review)*
- `tests/validation/terraform_native_test.sh`
- `tests/security/tflint_test.sh`
- `tests/security/checkov_test.sh`
- `tests/validation/cedar_syntax_test.sh`
- `.pre-commit-config.yaml`
- `.tflint.hcl`
- `.checkov.yaml`
- Updated `Makefile` with test targets

Verification:
```bash
make test-validate   # Passes
make test-security   # Zero critical issues
pre-commit run --all-files  # Passes
# All documentation files exist and are comprehensive
```

### Phase 2: Example Agents + GitLab CI (Days 6-10)
**Priority**: High
**Effort**: 4-5 days
**Cost**: $0 (CI only, no deployment)

Tasks:
- [ ] Create hello-world S3 example
- [ ] Create gateway-tool Titanic example (with Lambda)
- [ ] Copy deepresearch agent to examples
- [ ] Validate all examples locally
- [ ] Create GitLab CI pipeline (.gitlab-ci.yml)
- [ ] Set up WIF in dev AWS account
- [ ] Configure GitLab CI/CD variables
- [ ] Test CI pipeline (validate/lint stages only)

Deliverables:
- `examples/1-hello-world/` (agent + tfvars)
- `examples/2-gateway-tool/` (agent + Lambda + tfvars)
- `examples/3-deepresearch/` (agent + tfvars)
- `.gitlab-ci.yml` with 6 stages
- `docs/WIF_SETUP.md` (WIF instructions)
- `scripts/validate_examples.sh`

Verification:
```bash
# Local
bash scripts/validate_examples.sh  # All pass
terraform plan -var-file=examples/1-hello-world/terraform.tfvars  # Succeeds

# GitLab CI
# Push to feature branch → Pipeline runs validate/lint stages → Passes
```

---

### Phase 3: Backend Setup + State Management (Days 11-13)
**Priority**: High
**Effort**: 2-3 days
**Cost**: ~$1/month (S3 + DynamoDB)

Tasks:
- [ ] Create S3 state buckets (dev/test/prod)
- [ ] Create DynamoDB lock tables (dev/test/prod)
- [ ] Generate backend configs per environment
- [ ] Set up bucket versioning + encryption
- [ ] Configure lifecycle policies
- [ ] Test state migration
- [ ] Document state recovery procedures

Deliverables:
- `backend-dev.tf`, `backend-test.tf`, `backend-prod.tf`
- `scripts/setup_backend.sh` (creates S3 + DynamoDB)
- `scripts/migrate_state.sh` (migrates from local to S3)
- `docs/STATE_MANAGEMENT.md`

Verification:
```bash
# Initialize with backend
terraform init -backend-config=backend-dev.tf
terraform plan  # State in S3
terraform apply  # State locking works
terraform state list  # Verify state
```

---

### Phase 4: Unit Tests (Days 14-20) - Optional, Can Defer
**Priority**: Medium (defer to Phase 5 if time-constrained)
**Effort**: 5-7 days
**Cost**: ~$50-100 (Terratest deploys to AWS)

**Note**: This phase requires actual AWS deployments. Can be deferred if needed.

Tasks:
- [ ] Set up Terratest framework (Go)
- [ ] Create test fixtures (minimal/complete/secure)
- [ ] Implement foundation module tests
- [ ] Implement tools module tests
- [ ] Implement runtime module tests
- [ ] Implement governance module tests
- [ ] Add cleanup/destroy logic
- [ ] Integrate with CI (optional job)

Deliverables:
- `tests/unit/foundation_test.go`
- `tests/unit/tools_test.go`
- `tests/unit/runtime_test.go`
- `tests/unit/governance_test.go`
- `tests/fixtures/` (test data)
- `tests/helpers/terraform_helpers.go`

Verification:
```bash
cd tests/unit
go test -v -timeout 30m  # All tests pass
```

### Phase 5: Integration Tests + Full Deployment (Days 21-25)
**Priority**: Low (production deployment)
**Effort**: 4-5 days
**Cost**: ~$10-50/day (dev + test environments)

Tasks:
- [ ] Enable deploy-dev stage in GitLab CI
- [ ] Auto-deploy to dev on main branch merge
- [ ] Test dev deployment end-to-end
- [ ] Create manual deploy-test stage
- [ ] Create manual deploy-prod stage
- [ ] Set up approval workflows
- [ ] Configure deployment notifications (Slack/email) *(from DevOps review)*
- [ ] Document rollback procedures
- [ ] **Test rollback procedure in dev** *(from DevOps review)*
- [ ] **Add drift detection scheduled job** *(from DevOps review)*
- [ ] **Create CloudWatch dashboard** *(from DevOps review)*
- [ ] **Define SLOs and alert tiers** *(from DevOps review)*

Deliverables:
- Updated `.gitlab-ci.yml` with deploy stages
- `scripts/deploy.sh` (deployment script)
- `scripts/rollback.sh` (rollback script)
- `scripts/test_rollback.sh` *(NEW - from DevOps review)*
- `docs/DEPLOYMENT.md` (deployment guide)
- `docs/ROLLBACK.md` (rollback procedures)
- `docs/SLO.md` - SLO definitions and alert tiers *(NEW)*
- CloudWatch dashboard JSON export *(NEW)*
- Weekly drift detection CI job *(NEW)*

Verification:
```bash
# GitLab CI
# Merge to main → deploy-dev runs automatically → Dev environment updated
# Manual trigger test → deploy-test runs → Test environment updated
# Tag v1.0.0 → deploy-prod manual approval → Prod deployment
```

---

## Complete GitLab CI Pipeline Configuration

```yaml
# .gitlab-ci.yml
image: amazon/aws-cli:latest

stages:
  - validate     # Terraform syntax, formatting (no AWS)
  - lint         # Security scanning, best practices (no AWS)
  - test         # Example validation, Cedar policies (no AWS)
  - deploy-dev   # Auto-deploy to dev (AWS dev account)
  - deploy-test  # Manual deploy to test (AWS test account)
  - deploy-prod  # Manual deploy to prod (AWS prod account)

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/terraform
  TF_VERSION: "1.5.0"
  AWS_DEFAULT_REGION: us-east-1

# Install dependencies
before_script:
  - apk add --no-cache bash git wget unzip jq python3 py3-pip
  # Install Terraform
  - wget https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
  - unzip terraform_${TF_VERSION}_linux_amd64.zip
  - mv terraform /usr/local/bin/
  - terraform version
  # Install TFLint
  - wget -O- https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
  # Install Checkov
  - pip3 install checkov
  # Verify AWS credentials via WIF
  - |
    if [ -n "$CI_JOB_JWT_V2" ]; then
      export AWS_WEB_IDENTITY_TOKEN=$CI_JOB_JWT_V2
      export AWS_ROLE_SESSION_NAME="gitlab-${CI_PROJECT_PATH_SLUG}-${CI_PIPELINE_ID}"
      aws sts get-caller-identity
    fi

# ============================================================
# STAGE 1: VALIDATE (No AWS resources)
# ============================================================

validate:fmt:
  stage: validate
  script:
    - cd $TF_ROOT
    - terraform fmt -check -recursive
  only:
    - merge_requests
    - main
    - branches
  tags:
    - docker

validate:syntax:
  stage: validate
  script:
    - cd $TF_ROOT
    - terraform init -backend=false
    - terraform validate
  only:
    - merge_requests
    - main
    - branches
  tags:
    - docker

validate:plan:
  stage: validate
  script:
    - cd $TF_ROOT
    - terraform init -backend=false
    - terraform plan -var-file=examples/1-hello-world/terraform.tfvars -out=test.tfplan
    - terraform show test.tfplan
  artifacts:
    paths:
      - $TF_ROOT/test.tfplan
    expire_in: 1 hour
  only:
    - merge_requests
    - main
  tags:
    - docker

# ============================================================
# STAGE 2: LINT (No AWS resources)
# ============================================================

lint:tflint:
  stage: lint
  script:
    - cd $TF_ROOT
    - tflint --init
    - tflint --recursive --format compact
  allow_failure: true  # Warning only initially
  only:
    - merge_requests
    - main
  tags:
    - docker

lint:checkov:
  stage: lint
  script:
    - cd $TF_ROOT
    - checkov -d . --framework terraform --quiet --compact
  allow_failure: false  # Must pass
  only:
    - merge_requests
    - main
  tags:
    - docker
  artifacts:
    reports:
      junit: checkov-report.xml
    paths:
      - checkov-report.json
    expire_in: 30 days

# ============================================================
# STAGE 3: TEST (No AWS resources)
# ============================================================

test:examples:
  stage: test
  script:
    - cd $TF_ROOT
    - bash ../scripts/validate_examples.sh
  only:
    - merge_requests
    - main
  tags:
    - docker

test:cedar-policies:
  stage: test
  before_script:
    - apk add --no-cache rust cargo
    - cargo install cedar-policy-cli
  script:
    - cd $TF_ROOT
    - |
      for policy in modules/agentcore-governance/cedar_policies/*.cedar; do
        echo "Validating: $policy"
        cedar validate --policies "$policy"
      done
  only:
    - merge_requests
    - main
  tags:
    - docker

test:documentation:
  stage: test
  script:
    - cd $TF_ROOT
    - |
      # Check for broken links in documentation
      for doc in *.md; do
        echo "Checking: $doc"
        # Check for broken internal links
        grep -o '\[.*\](.*\.md)' "$doc" || true
      done
  allow_failure: true
  only:
    - merge_requests
    - main
  tags:
    - docker

# ============================================================
# STAGE 4: DEPLOY DEV (Auto on main merge)
# ============================================================

deploy:dev:
  stage: deploy-dev
  environment:
    name: dev
    url: https://console.aws.amazon.com/bedrock/
  variables:
    AWS_ROLE_ARN: $CI_ENVIRONMENT_ROLE_ARN_DEV
    TF_STATE_BUCKET: $TF_STATE_BUCKET_DEV
    TF_VAR_environment: "dev"
  before_script:
    - !reference [before_script]
    - export AWS_ROLE_ARN=$CI_ENVIRONMENT_ROLE_ARN_DEV
  script:
    - cd $TF_ROOT
    # Initialize with dev backend
    - |
      cat > backend-dev.tf <<EOF
      terraform {
        backend "s3" {
          bucket         = "${TF_STATE_BUCKET}"
          key            = "agentcore/terraform.tfstate"
          region         = "${AWS_DEFAULT_REGION}"
          encrypt        = true
          dynamodb_table = "terraform-state-lock-dev"
        }
      }
      EOF
    - terraform init -reconfigure
    - terraform plan -var-file=examples/1-hello-world/terraform.tfvars -out=dev.tfplan
    - terraform apply -auto-approve dev.tfplan
    - terraform output -json > outputs-dev.json
  artifacts:
    paths:
      - $TF_ROOT/outputs-dev.json
    expire_in: 7 days
  only:
    - main
  tags:
    - docker

# ============================================================
# STAGE 5: DEPLOY TEST (Manual approval)
# ============================================================

deploy:test:
  stage: deploy-test
  environment:
    name: test
    url: https://console.aws.amazon.com/bedrock/
  variables:
    AWS_ROLE_ARN: $CI_ENVIRONMENT_ROLE_ARN_TEST
    TF_STATE_BUCKET: $TF_STATE_BUCKET_TEST
    TF_VAR_environment: "test"
  before_script:
    - !reference [before_script]
    - export AWS_ROLE_ARN=$CI_ENVIRONMENT_ROLE_ARN_TEST
  script:
    - cd $TF_ROOT
    - |
      cat > backend-test.tf <<EOF
      terraform {
        backend "s3" {
          bucket         = "${TF_STATE_BUCKET}"
          key            = "agentcore/terraform.tfstate"
          region         = "${AWS_DEFAULT_REGION}"
          encrypt        = true
          dynamodb_table = "terraform-state-lock-test"
        }
      }
      EOF
    - terraform init -reconfigure
    - terraform plan -var-file=examples/2-gateway-tool/terraform.tfvars -out=test.tfplan
    - terraform apply -auto-approve test.tfplan
    - terraform output -json > outputs-test.json
  artifacts:
    paths:
      - $TF_ROOT/outputs-test.json
    expire_in: 30 days
  when: manual
  only:
    - /^release\/.*$/
  tags:
    - docker

# ============================================================
# STAGE 6: DEPLOY PROD (Manual approval, tags only)
# ============================================================

deploy:prod:
  stage: deploy-prod
  environment:
    name: production
    url: https://console.aws.amazon.com/bedrock/
  variables:
    AWS_ROLE_ARN: $CI_ENVIRONMENT_ROLE_ARN_PROD
    TF_STATE_BUCKET: $TF_STATE_BUCKET_PROD
    TF_VAR_environment: "prod"
  before_script:
    - !reference [before_script]
    - export AWS_ROLE_ARN=$CI_ENVIRONMENT_ROLE_ARN_PROD
  script:
    - cd $TF_ROOT
    - |
      cat > backend-prod.tf <<EOF
      terraform {
        backend "s3" {
          bucket         = "${TF_STATE_BUCKET}"
          key            = "agentcore/terraform.tfstate"
          region         = "${AWS_DEFAULT_REGION}"
          encrypt        = true
          dynamodb_table = "terraform-state-lock-prod"
        }
      }
      EOF
    - terraform init -reconfigure
    - terraform plan -var-file=examples/3-deepresearch/terraform.tfvars -out=prod.tfplan
    - echo "Waiting for manual approval..."
    - terraform apply -auto-approve prod.tfplan
    - terraform output -json > outputs-prod.json
  artifacts:
    paths:
      - $TF_ROOT/outputs-prod.json
    expire_in: 90 days
  when: manual
  only:
    - tags
  tags:
    - docker
```

---

## GitLab CI/CD Variables Configuration

Configure these in GitLab Settings → CI/CD → Variables:

```
# AWS Roles (WIF)
CI_ENVIRONMENT_ROLE_ARN_DEV:  arn:aws:iam::111111111111:role/gitlab-terraform-deployer-dev
CI_ENVIRONMENT_ROLE_ARN_TEST: arn:aws:iam::222222222222:role/gitlab-terraform-deployer-test
CI_ENVIRONMENT_ROLE_ARN_PROD: arn:aws:iam::333333333333:role/gitlab-terraform-deployer-prod

# State Buckets
TF_STATE_BUCKET_DEV:  terraform-state-dev-12345
TF_STATE_BUCKET_TEST: terraform-state-test-12345
TF_STATE_BUCKET_PROD: terraform-state-prod-12345

# Optional: Secrets Manager paths
SECRETS_PATH_DEV:  agentcore/dev
SECRETS_PATH_TEST: agentcore/test
SECRETS_PATH_PROD: agentcore/prod
```

### Phase 4: Example & Policy Validation (Week 4)
**Priority**: Medium
**Effort**: 2-3 days

Tasks:
- [ ] Implement example validation script
- [ ] Implement Cedar policy validation
- [ ] Implement output verification tests
- [ ] Implement packaging tests
- [ ] Update documentation

Deliverables:
- `scripts/validate_examples.sh`
- `tests/validation/cedar_syntax_test.sh`
- `tests/validation/outputs_test.sh`
- `tests/validation/packaging_test.sh`

### Phase 5: Documentation & CI/CD Enhancement (Week 5)
**Priority**: Low
**Effort**: 1-2 days

Tasks:
- [ ] Create test documentation (TEST_GUIDE.md)
- [ ] Update main README with testing section
- [ ] Add test badges to README
- [ ] Create test coverage reports
- [ ] Final CI/CD optimization

Deliverables:
- `TEST_GUIDE.md`
- Updated `README.md`
- Coverage reports
- Optimized CI/CD workflows

---

## Test Execution Strategy

### Local Development
```bash
# Run all tests
make test-all

# Run specific test categories
make test-validate      # Terraform native validation
make test-security      # Security scans
make test-unit          # Unit tests
make test-integration   # Integration tests
make test-examples      # Example validation
```

### CI/CD Pipeline
```
On Push/PR:
1. Format check (fail fast)
2. Syntax validation (all modules)
3. Security scanning (Checkov + TFLint)
4. Unit tests (dry-run, no AWS resources)
5. Example validation (plan only)
6. Cedar policy validation

On Release/Tag:
1. Full integration tests (deploy to test AWS account)
2. End-to-end validation
3. Cleanup test resources
```

### Test Environments
- **Local**: Developer workstation (validate, plan, unit tests)
- **CI**: GitHub Actions (all tests, no actual deployment)
- **Test AWS Account**: Integration tests with real resources (isolated)
- **Production**: No tests, only validated releases

---

## Test Coverage Goals

### Target Metrics
- **Terraform Syntax**: 100% (all files validate)
- **Security Scan**: 0 critical/high issues
- **Unit Tests**: 80%+ code coverage
- **Integration Tests**: All deployment patterns
- **Example Validation**: 100% (all examples work)
- **Policy Validation**: 100% (all Cedar policies valid)

### Coverage Tracking
```bash
# Generate coverage report
go test -cover -coverprofile=coverage.out ./tests/...
go tool cover -html=coverage.out -o coverage.html

# Check coverage threshold
COVERAGE=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
if (( $(echo "$COVERAGE < 80" | bc -l) )); then
    echo "Coverage $COVERAGE% is below 80%"
    exit 1
fi
```

---

## Verification Checklist

After implementing tests:
- [ ] All Terraform files validate
- [ ] No security scan failures
- [ ] Unit tests pass for all modules
- [ ] Integration tests deploy successfully
- [ ] All examples validate
- [ ] Cedar policies pass validation
- [ ] CI/CD pipeline runs successfully
- [ ] Documentation updated
- [ ] Test coverage meets goals
- [ ] Makefile targets work

---

## Success Criteria

### Must Have (MVP)
- ✅ Terraform native validation (format, validate, plan)
- ✅ Security scanning (Checkov + TFLint)
- ✅ Basic CI/CD pipeline
- ✅ Example validation

### Should Have (Complete)
- ✅ Unit tests for all modules (Terratest)
- ✅ Integration tests for deployment patterns
- ✅ Cedar policy validation
- ✅ Output verification tests
- ✅ Test documentation

### Nice to Have (Advanced)
- ⭕ End-to-end tests with real AWS deployment
- ⭕ Performance benchmarks
- ⭕ Drift detection tests
- ⭕ Cost estimation validation
- ⭕ Multi-region deployment tests

---

## Files to Create

### Test Files (20+ files)
1. `tests/validation/terraform_native_test.sh`
2. `tests/security/checkov_scan.sh`
3. `tests/security/tflint_scan.sh`
4. `tests/unit/foundation_test.go`
5. `tests/unit/tools_test.go`
6. `tests/unit/runtime_test.go`
7. `tests/unit/governance_test.go`
8. `tests/integration/minimal_agent_test.go`
9. `tests/integration/full_agent_test.go`
10. `tests/integration/secure_prod_test.go`
11. `tests/examples/research_agent_test.go`
12. `tests/examples/support_agent_test.go`
13. `tests/validation/cedar_syntax_test.sh`
14. `tests/validation/outputs_test.sh`
15. `tests/validation/packaging_test.sh`
16. `tests/helpers/terraform_helpers.go`
17. `tests/fixtures/minimal/terraform.tfvars`
18. `tests/fixtures/complete/terraform.tfvars`
19. `tests/fixtures/secure/terraform.tfvars`
20. `scripts/test_all.sh`

### CI/CD Files (3 files)
1. `.github/workflows/test.yml`
2. `.github/workflows/security.yml`
3. `.github/workflows/release.yml`

### Documentation (2 files)
1. `TEST_GUIDE.md`
2. Updated `README.md` with testing section

### Makefile Updates
- Add test targets to existing Makefile

---

## Risk Mitigation

### Risk 1: AWS Costs from Integration Tests
**Mitigation**:
- Use terraform plan (no apply) in CI
- Integration tests only on dedicated test account
- Auto-cleanup with terraform destroy
- Set budget alerts

### Risk 2: Test Execution Time
**Mitigation**:
- Parallel test execution
- Caching of dependencies
- Skip long-running tests in PR checks
- Full suite only on main branch

### Risk 3: False Positives in Security Scans
**Mitigation**:
- Configure suppressions for known safe patterns
- Document exceptions in README
- Regular review of suppression list

### Risk 4: Terratest Dependencies
**Mitigation**:
- Pin dependency versions
- Use Go modules
- Container-based test execution
- Fallback to bash scripts if needed

---

## Next Steps

1. **Review this plan** - Ensure all requirements covered
2. **Choose test framework** - Terratest vs Kitchen-Terraform
3. **Set up test AWS account** - Isolated environment
4. **Implement Phase 1** - Foundation tests
5. **Iterate through phases** - Week by week
6. **Document as you go** - Keep TEST_GUIDE updated
7. **Integrate with CI/CD** - Automate everything

---

## References

- **Terratest**: https://terratest.gruntwork.io/
- **Kitchen-Terraform**: https://github.com/newcontext-oss/kitchen-terraform
- **Checkov**: https://www.checkov.io/
- **TFLint**: https://github.com/terraform-linters/tflint
- **Cedar CLI**: https://www.cedarpolicy.com/en/tutorial/cli
- **Terraform Testing**: https://www.terraform.io/docs/language/modules/testing-experiment.html

---

## Complete Implementation Timeline

### Summary by Phase

| Phase | Duration | Cost | AWS Required | Blocking |
|-------|----------|------|--------------|----------|
| Phase 0: Critical Fixes | 1-2 days | $0 | No | **YES** |
| Phase 1: Local Testing | 2-3 days | $0 | No | No |
| Phase 2: Examples + CI | 4-5 days | $0 | No | No |
| Phase 3: Backend Setup | 2-3 days | $1/month | Yes (setup) | No |
| Phase 4: Unit Tests | 5-7 days | $50-100 | Yes | No |
| Phase 5: Deployment | 4-5 days | $10-50/day | Yes | No |
| **TOTAL (MVP)** | **9-13 days** | **~$50** | **Minimal** | - |
| **TOTAL (Complete)** | **18-25 days** | **~$200** | **Yes** | - |

### MVP Recommendation (Phases 0-3)

**What You Get**:
- ✅ All critical security issues fixed
- ✅ Local testing (100% AWS-free development)
- ✅ Three working examples
- ✅ GitLab CI pipeline
- ✅ Pre-commit hooks
- ✅ Dev environment deployable

**Timeline**: 9-13 days | **Cost**: ~$50 | **Production Ready**: Dev/Test

---

## Success Criteria

- [ ] Phase 0: Zero critical security issues (Checkov clean)
- [ ] Phase 1: 100% local testing without AWS account
- [ ] Phase 2: Three examples deploy successfully
- [ ] Phase 3: State in S3 with locking
- [ ] MVP: Dev environment functional via GitLab CI

---

## Key Decisions

1. **GitLab CI (On-Prem)** with WIF authentication
2. **Branch/Tag Promotion**: main → release/* → tags (v*)
3. **S3 Backend** with DynamoDB locking per environment
4. **Three Examples**: hello-world (S3), gateway-tool (Titanic), deepresearch (full)
5. **Maximum Local Testing**: Developers never need AWS for validation
6. **Pre-commit Hooks**: Enforce quality before push (GitHub initially)
7. **Unit Tests Optional**: Defer to Phase 4 if needed

---

## Status

**Current**: Implementation has CRITICAL security issues - **NOT PRODUCTION READY**
**After Phase 0**: Security fixed - **Dev/Test Ready**
**After Phase 3 (MVP)**: Full pipeline - **Production Ready for Dev/Test**
**After Phase 5 (Complete)**: Enterprise-grade - **Production Ready for All Environments**

**Recommended Path**: Execute Phases 0-3 (MVP), defer 4-5 unless full automation needed.

**Senior Engineer Review**: `C:\Users\julia\.claude\plans\snoopy-watching-meerkat-agent-a6c207e.md`

---

## APPENDIX A: Documentation File Specifications

### docs/adr/ - Architecture Decision Records

**Purpose**: Track key architectural decisions for future reference

**Template**: Use [MADR format](https://adr.github.io/madr/)

**Files to Create**:

#### docs/adr/0001-module-structure.md
```markdown
# ADR 0001: Four-Module Architecture Structure

## Status
Accepted

## Context
Need to organize AWS Bedrock AgentCore resources into logical, maintainable modules.
Original implementation had only 1 module. Need clear separation of concerns.

## Decision
Implement 4-module architecture:
1. agentcore-foundation (Gateway, Identity, Observability) - Terraform-native
2. agentcore-tools (Code Interpreter, Browser) - Terraform-native
3. agentcore-runtime (Runtime, Memory, Packaging) - CLI-based
4. agentcore-governance (Policies, Evaluations) - CLI-based

## Rationale
- Clear separation between Terraform-native vs CLI-based resources
- Foundation provides base infrastructure for other modules
- Tools are independent capabilities that can be enabled/disabled
- Runtime handles execution lifecycle
- Governance enforces security and quality

## Consequences
**Positive**:
- Modular, reusable components
- Clear dependency graph
- Easy to enable/disable features
- Better testability

**Negative**:
- More complex than single module
- Need to manage inter-module dependencies

## Alternatives Considered
1. Single monolithic module - Rejected (too complex)
2. 9 separate modules (one per feature) - Rejected (too granular)
```

#### docs/adr/0002-cli-based-resources.md
```markdown
# ADR 0002: CLI-Based Resources via null_resource

## Status
Accepted

## Context
7/13 AWS Bedrock AgentCore resources don't exist in Terraform AWS provider yet:
- Runtime, Memory, Policy Engine, Evaluators, Credential Providers

Validation with terraform-mcp-server confirmed resource gaps.

## Decision
Use `null_resource` with `local-exec` provisioner + AWS CLI for missing resources.
Pattern: AWS CLI → JSON output → `data.external` → Terraform outputs

## Rationale
- Allows immediate implementation without waiting for AWS provider updates
- Maintains infrastructure-as-code principles
- State management via file outputs + external data sources
- Clear migration path when native resources become available

## Consequences
**Positive**:
- Can deploy full feature set immediately
- Documented patterns for future migration
- Idempotent with hash-based triggers

**Negative**:
- Requires AWS CLI availability
- State stored in local files (less reliable than native resources)
- More complex than native Terraform

## Migration Path
When AWS provider adds native resources:
1. Run `terraform import` for CLI-created resources
2. Replace `null_resource` with native resource
3. Update outputs to use native attributes
4. Remove data.external sources
5. Clean up .terraform/*.json files
```

#### docs/adr/0003-gitlab-ci-pipeline.md
```markdown
# ADR 0003: GitLab CI/CD with Web Identity Federation

## Status
Accepted

## Context
Need CI/CD pipeline for automated testing and deployment.
GitLab on-premises infrastructure available.
Three AWS accounts (dev, test, prod) for environments.

## Decision
Use GitLab CI with:
- 6 stages (validate, lint, test, deploy-dev, deploy-test, deploy-prod)
- AWS Web Identity Federation (WIF) for authentication
- Branch-based promotion (main → release/* → tags)
- Maximum local testing (no AWS for validate/lint/test stages)

## Rationale
- GitLab already deployed on-prem
- WIF more secure than static IAM credentials
- Branch/tag strategy provides clear promotion path
- Local testing reduces AWS costs

## Consequences
**Positive**:
- No AWS credentials stored in GitLab
- Clear environment promotion workflow
- Zero-cost testing (local only)
- Audit trail via git history

**Negative**:
- Initial WIF setup complexity
- Requires GitLab admin access
- Need separate OIDC provider per AWS account

## Alternatives Considered
1. Static IAM credentials - Rejected (security risk)
2. GitHub Actions - Rejected (repo on GitHub temporarily, but target is GitLab)
3. Jenkins - Rejected (GitLab already available)
```

#### docs/adr/0004-state-management.md
```markdown
# ADR 0004: S3 Backend with DynamoDB Locking

## Status
Accepted

## Context
Need remote state storage for team collaboration and state locking.
Three AWS accounts (dev, test, prod) with separate state.

## Decision
Use S3 backend with:
- Separate bucket per environment (terraform-state-{env}-{id})
- DynamoDB table for state locking (terraform-state-lock-{env})
- Bucket versioning enabled (state backup/rollback)
- Encryption at rest (AES256 or KMS)

## Rationale
- S3 provides reliable, durable state storage
- DynamoDB locking prevents concurrent modifications
- Versioning enables rollback if needed
- Separate buckets provide blast radius containment

## Consequences
**Positive**:
- Team can collaborate safely
- State history maintained
- Disaster recovery via versioning
- Low cost (~$1/month per environment)

**Negative**:
- Must create buckets/tables before terraform init
- Requires S3 + DynamoDB permissions
- State contains sensitive data (must encrypt)

## State Structure
```
s3://terraform-state-{env}-{id}/
└── agentcore/
    └── terraform.tfstate
```
```

#### docs/adr/0005-secrets-strategy.md
```markdown
# ADR 0005: Hybrid Secrets Management

## Status
Accepted

## Context
Need to manage secrets across environments:
- Infrastructure config (Lambda ARNs, bucket names)
- Runtime secrets (API keys, OAuth tokens)
- CI/CD variables

## Decision
Two-tier approach:
1. **GitLab CI/CD Variables**: Infrastructure config (non-secret)
   - AWS role ARNs
   - State bucket names
   - Region settings

2. **AWS Secrets Manager**: Runtime secrets (sensitive)
   - MCP Lambda configurations
   - OAuth credentials
   - External API keys

## Rationale
- Separation of concerns (infra vs. runtime secrets)
- GitLab variables for CI/CD automation
- AWS Secrets Manager for application-level secrets
- Secrets stay in AWS (not in Terraform state)

## Consequences
**Positive**:
- Secrets not in Terraform state
- Rotation via AWS Secrets Manager
- Access control via IAM
- Audit logging

**Negative**:
- Two systems to manage
- Additional AWS costs (~$0.40/secret/month)
- Runtime must have Secrets Manager permissions

## Secret Naming Convention
```
agentcore/{environment}/{secret-type}
Examples:
- agentcore/dev/mcp-lambda-arns
- agentcore/dev/oauth-credentials
- agentcore/prod/api-keys
```
```

#### docs/adr/0008-aws-managed-encryption.md
```markdown
# ADR 0008: AWS-Managed Encryption by Default

## Status
Accepted

## Context
Customer-managed KMS keys add operational complexity and cost without providing meaningful security benefits for most use cases. AWS-managed encryption (SSE-S3, default CloudWatch encryption) provides equivalent protection while simplifying operations.

## Decision
Use **AWS-managed encryption** (SSE-S3) by default for:
- S3 buckets (deployment artifacts, outputs, state)
- CloudWatch Logs (default encryption)
- Secrets Manager (default AWS-managed key)

Only use **customer-managed KMS** when:
- Regulatory requirements explicitly mandate customer-controlled keys
- Cross-account encryption is required
- Custom key rotation schedules are mandated

## Implementation
```hcl
# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  bucket = aws_s3_bucket.deployment.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # AWS-managed
    }
  }
}
```

## References
- See `CLAUDE.md` Rule 1.6 for full rationale
- [AWS S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
```

#### docs/adr/0009-agent-discovery-identity.md (PRE-ADR)
```markdown
# ADR 0009: Agent Discovery and Identity Propagation

## Status
**Proposed** (Pre-ADR - requires approval before implementation)

## Context
CLAUDE.md RULE 9 and RULE 10 define requirements for agent discovery and identity propagation in multi-agent systems:
- RULE 9: Discovery is EXPLICIT
- RULE 10: Identity Propagation is MANDATORY

This pre-ADR outlines how to implement these rules in the Terraform infrastructure.

## Proposal

### Rule 9: Discovery is EXPLICIT

**9.1: Agents Must Be Discoverable**
- Every agent MUST expose `/.well-known/agent-card.json` endpoint
- Agents MUST register with AWS Cloud Map (East-West) or Gateway Manifest (Northbound)
- FORBIDDEN: Hardcoding agent endpoints in application code

**9.2: Gateway is the Tool Source**
- Tools (Lambda functions) MUST be accessed via AgentCore Gateway
- FORBIDDEN: Direct `lambda:InvokeFunction` calls to tools

### Rule 10: Identity Propagation is MANDATORY

**10.1: No Anonymous A2A Calls**
- All Agent-to-Agent calls MUST use Workload Token
- Pattern: `GetWorkloadAccessTokenForJWT` → `Authorization: Bearer <token>`

**10.2: User Context Must Persist**
- Original user identity (Entra ID/Cognito) MUST propagate through agent chains
- Enables per-user guardrails and audit trail

## Proposed Implementation

### Agent Card Endpoint
```json
{
  "agentId": "research-agent-v1",
  "name": "Deep Research Agent",
  "version": "1.0.0",
  "capabilities": ["research", "synthesis"],
  "endpoints": {
    "invoke": "https://api.example.com/agents/research/invoke"
  },
  "authentication": {
    "type": "workload-token",
    "audience": "urn:agent:research"
  }
}
```

### Terraform Changes Required
```hcl
# Cloud Map namespace
resource "aws_service_discovery_private_dns_namespace" "agents" {
  name = "agents.internal"
  vpc  = var.vpc_id
}

# Workload Identity (CLI-based)
resource "null_resource" "workload_identity" {
  count = var.enable_identity ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore-control create-workload-identity \
        --agent-id ${var.agent_name} \
        --audience "urn:agent:${var.agent_name}" \
        --output json > ${path.module}/.terraform/identity_output.json
    EOT
  }
}
```

## Open Questions (Require Resolution Before Acceptance)

1. **Scope**: Is this required for ALL agents or only multi-agent systems?
2. **Timeline**: Should this be Phase 1 or deferred to Phase 3+?
3. **VPC Requirement**: Does Cloud Map require VPC mode (impacts cost)?
4. **Backward Compatibility**: How do existing agents migrate?
5. **Testing**: How to test workload token exchange without production setup?

## Cost Impact (Estimated)
- Cloud Map: ~$1/month per agent (namespace + service)
- Workload Identity: Minimal (STS API calls)
- VPC endpoints (if required): ~$7/month per AZ

## Next Steps
1. **Discuss** requirements with team
2. **Clarify** scope and timeline
3. **Prototype** workload token exchange
4. **Test** in dev environment
5. **Update status** to "Accepted" if approved
6. **Implement** in agreed phase

## References
- [CLAUDE.md RULE 9](../CLAUDE.md#rule-9-discovery-is-explicit)
- [CLAUDE.md RULE 10](../CLAUDE.md#rule-10-identity-propagation-is-mandatory)
- [AWS Cloud Map](https://docs.aws.amazon.com/cloud-map/)
- [Workload Identity](https://aws.amazon.com/blogs/security/workload-identity/)
```

---

### CLAUDE.md (Project Root) - Development Rules & Principles for AI Coding Agents

**Location**: `terraform/CLAUDE.md` (NOT in docs/ - must be at project root for Claude Code to auto-load)

**Purpose**: Prescriptive rules and anti-patterns for AI agents working on this Terraform codebase

**Note**: Claude Code automatically reads `CLAUDE.md` from the project root. This file will be loaded every time Claude Code opens this project.

```markdown
# Development Rules & Principles for AI Coding Agents
## Bedrock AgentCore Terraform

> **Critical**: This is NOT a typical Terraform project. Read ALL rules before making ANY changes.

---

## RULE 1: Security is NON-NEGOTIABLE

### Critical Security Findings (From Senior Engineer Review)

**5 DEPLOYMENT BLOCKERS identified**:
1. IAM wildcard resources (3 instances)
2. Dynamic block syntax errors
3. Error suppression masking failures
4. Placeholder ARN validation missing
5. Dependency package limits

### Security Rules - NEVER Violate These

#### Rule 1.1: IAM Resources MUST Be Specific
```hcl
❌ FORBIDDEN:
Resource = "*"

✅ REQUIRED:
Resource = [
  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
]
Condition = {
  StringEquals = {
    "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  }
}
```

**Why**: Wildcard resources violate least privilege. Senior engineer review flagged 3 instances in `iam.tf:46, 54, 94`.

**When to apply**: EVERY IAM policy. No exceptions.

#### Rule 1.2: Errors MUST Fail Fast
```bash
❌ FORBIDDEN:
cp -r "${local.source_path}"/* "$BUILD_DIR/code/" 2>/dev/null || true

✅ REQUIRED:
if [ ! -d "${local.source_path}" ]; then
  echo "ERROR: Source path not found: ${local.source_path}"
  exit 1
fi
cp -r "${local.source_path}"/* "$BUILD_DIR/code/"
```

**Why**: Error suppression (`|| true`, `2>/dev/null`) masks deployment failures, causing silent breakage in production.

**When to apply**: ALL bash provisioners in `null_resource` blocks.

#### Rule 1.3: Dynamic Blocks Only for Collections
```hcl
❌ FORBIDDEN:
dynamic "kms_key_arn" {
  for_each = var.enable_kms ? [aws_kms_key.agentcore[0].arn] : []
  content {
    value = kms_key_arn.value
  }
}

✅ REQUIRED:
kms_key_arn = var.enable_kms ? aws_kms_key.agentcore[0].arn : null
```

**Why**: `dynamic` is for blocks, not simple attributes. This causes validation failures (`gateway.tf:77-82`).

**When to apply**: Use `dynamic` ONLY for repeatable blocks (like `ingress` rules), NEVER for single attributes.

#### Rule 1.4: Validate ALL User Inputs
```hcl
✅ REQUIRED:
variable "mcp_targets" {
  validation {
    condition = alltrue([
      for k, v in var.mcp_targets :
      !can(regex("123456789012", v.lambda_arn))
    ])
    error_message = "Placeholder ARNs detected. Replace 123456789012 with actual account ID."
  }
}
```

**Why**: Placeholder ARNs in examples cause production failures. Validation prevents deployment with invalid values.

**When to apply**: ALL variables accepting ARNs, URLs, or account IDs.

#### Rule 1.5: No Arbitrary Limits
```bash
❌ FORBIDDEN:
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}" | head -20)

✅ REQUIRED:
-r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
```

**Why**: `head -20` artificially limits dependencies to 20 packages, breaking projects with more deps.

**When to apply**: NEVER use `head`/`tail` unless explicitly paginating output for humans.

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
    ↓
    ├─→ agentcore-tools (depends: foundation)
    ├─→ agentcore-runtime (depends: foundation)
    │       ↓
    │   agentcore-governance (depends: foundation + runtime)
    └─→ agentcore-governance (depends: foundation + runtime)
```

### Rule 2.1: Dependency Direction NEVER Reverses
❌ **FORBIDDEN**: Runtime depending on Governance
❌ **FORBIDDEN**: Foundation depending on any other module
✅ **ALLOWED**: Governance depending on Runtime

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
✅ REQUIRED PATTERN:
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
Stage 1: validate (fmt, validate, plan) → NO AWS
Stage 2: lint (tflint, checkov)        → NO AWS
Stage 3: test (examples, policies)     → NO AWS
Stage 4: deploy-dev (auto)             → AWS DEV account
Stage 5: deploy-test (manual)          → AWS TEST account
Stage 6: deploy-prod (manual)          → AWS PROD account
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

**Why**: OCDS pattern separates slow deps from fast code changes. Deps cached between builds.

### Rule 5.2: Hash-Based Triggers Are REQUIRED
```hcl
triggers = {
  # Deps trigger
  dependencies_hash = filemd5(local.dependencies_file)
  # Code trigger
  source_hash = sha256(join("", [for f in fileset(local.source_path, "**") : filesha256("${local.source_path}/${f}")]))
}
```

**Why**: Without hashes, Terraform can't detect changes and won't rebuild.

---

## RULE 6: GitLab CI Uses WIF, Not Credentials

### Rule 6.1: NEVER Store AWS Credentials in GitLab
❌ **FORBIDDEN**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` in CI/CD variables
✅ **REQUIRED**: Web Identity Federation with OIDC

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
✅ CORRECT:
terraform {
  backend "s3" {
    bucket = "terraform-state-dev-12345"   # Dev account
    key    = "agentcore/terraform.tfstate"
  }
}

❌ FORBIDDEN:
terraform {
  backend "s3" {
    bucket = "shared-state"
    key    = "agentcore/${var.environment}/terraform.tfstate"  # Don't interpolate
  }
}
```

**Why**: Separate AWS accounts = separate state buckets. No workspace isolation needed.

---

## RULE 7: Common Tasks Have Standard Procedures

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
1. Check `docs/architecture.md` "Current State vs Planned State" section
2. Reference the 5 critical issues table (SEC-001 through SEC-006)
3. Apply fix per Rule 1 (Security)
4. Test: `checkov -d . --framework terraform`
5. Verify: `terraform validate && terraform plan`
6. Update docs with fix details in SAME commit

### Creating a New Example
1. Create `examples/N-name/agent-code/runtime.py`
2. Create `examples/N-name/terraform.tfvars`
3. Test: `terraform plan -var-file=examples/N-name/terraform.tfvars`
4. Add validation to `scripts/validate_examples.sh`
5. Document in `examples/N-name/README.md`

---

---

## DECISION FRAMEWORK

| Question | Answer |
|----------|--------|
| Terraform-native or CLI? | Check if `aws_bedrockagentcore_X` exists. If YES: native. If NO: CLI pattern (Rule 3.1) |
| Which module? | Foundation=Gateway/Identity/Observability, Tools=CodeInterpreter/Browser, Runtime=Runtime/Memory/S3, Governance=Policies/Evaluations |
| Use dynamic block? | ONLY for repeatable blocks (ingress rules). NEVER for simple attributes. |
| New module? | NO. 4-module architecture is fixed. Ask if unsure. |

---

## FILE ORGANIZATION: Key Locations

```
terraform/
├── modules/                    # 4 core modules (MR required for changes)
│   ├── agentcore-foundation/   # Gateway, Identity, Observability
│   ├── agentcore-tools/        # Code Interpreter, Browser
│   ├── agentcore-runtime/      # Runtime, Memory, Packaging
│   └── agentcore-governance/   # Policies, Evaluations
├── examples/                   # 3 working examples
├── tests/                      # validation/ and security/ tests
├── docs/adr/                   # Architecture Decision Records
├── scripts/                    # Helper utilities
├── CLAUDE.md                   # This file (AI agent rules)
├── DEVELOPER_GUIDE.md          # Human onboarding
└── README.md                   # User documentation
```

**Full file listing**: See `DEVELOPER_GUIDE.md` for complete structure.

---

---

## CHECKLIST: Before Every Commit

```bash
# 1. Format (MUST pass)
terraform fmt -check -recursive

# 2. Validate (MUST pass)
terraform validate

# 3. Plan (MUST succeed)
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars

# 4. Security (MUST be clean)
checkov -d . --framework terraform --compact

# 5. Lint (MUST pass)
tflint --recursive

# 6. Pre-commit hooks (MUST pass)
pre-commit run --all-files

# ALL MUST PASS BEFORE PUSHING
```

---

## CHECKLIST: Before Requesting Review

- [ ] All commits follow conventional commits format
- [ ] Security checklist passed (above)
- [ ] Examples validated (if examples changed)
- [ ] Documentation updated (if architecture changed)
- [ ] ADR created (if design decision made)
- [ ] Tests added (if new feature added)
- [ ] Senior engineer review findings addressed (if applicable)

---

## QUICK REFERENCE: Common Commands

```bash
# Validate everything
make test-all

# Format code
terraform fmt -recursive

# Security scan
checkov -d . --framework terraform

# Test example
terraform plan -var-file=examples/1-hello-world/terraform.tfvars

# View state
terraform state list

# Show outputs
terraform output

# Clean up
terraform destroy

# Help
terraform --help
make help
```

---

## VERSION REQUIREMENTS

- **Terraform**: `1.5.7` (pinned via `.terraform-version`)
- **AWS Provider**: `~> 5.30` (allows 5.30.x, blocks 5.31+) *(Updated per DevOps review)*
- **null Provider**: `~> 3.2`
- **external Provider**: `~> 2.3`
- **Python**: 3.12 (for agent code)
- **AWS CLI**: >= 2.0
- **Checkov**: >= 3.0
- **TFLint**: >= 0.50

**Note**: Use `.terraform-version` file for tfenv/asdf version management.

---

## GETTING HELP

1. **This file** (claude.md) - Rules and principles
2. **architecture.md** - System design and data flows
3. **DEVELOPER_GUIDE.md** - Human-friendly onboarding
4. **ADRs** (docs/adr/) - Design decision history
5. **Senior engineer review** - Security findings and recommendations
6. **Plan file** - Comprehensive test and validation strategy

---

## RULE 8: Documentation MUST Match Code (ENFORCED)

### The Sync Rule
**Every code change MUST have corresponding documentation update in the SAME commit.**

```bash
# BEFORE committing, verify:
git diff --name-only | grep -E '\.(tf|py)$' && \
git diff --name-only | grep -E '\.(md)$' || \
echo "❌ VIOLATION: Code changed but no docs updated"
```

### What Must Stay In Sync

| Code Change | Required Doc Update |
|-------------|---------------------|
| New variable | README.md variables table + CLAUDE.md if security-related |
| New resource | architecture.md + module README |
| Bug fix | CLAUDE.md anti-patterns (if security) |
| New module | architecture.md + CLAUDE.md module section |
| New example | README.md examples section |
| API change | All affected docs |

### Enforcement Mechanism

Add to `.pre-commit-config.yaml`:
```yaml
- repo: local
  hooks:
    - id: docs-sync-check
      name: Check docs updated with code
      entry: bash -c 'git diff --cached --name-only | grep -qE "\.(tf|py)$" && git diff --cached --name-only | grep -qE "\.md$" || (echo "ERROR: Code changed without doc update" && exit 1)'
      language: system
      pass_filenames: false
```

### Violation Consequences
- PR will be **REJECTED** if code changes without doc updates
- Exception: Pure refactoring with no behavior change (must note in commit message)

---

## SUMMARY: The Golden Rules

1. **Security First**: No wildcards, no error suppression, validate everything
2. **Module Boundaries**: Foundation → Tools/Runtime → Governance (never reverse)
3. **CLI Pattern**: Use Rule 3.1 for all CLI-based resources
4. **Local Testing**: Validate locally before touching AWS
5. **Two-Stage Build**: OCDS pattern for packaging
6. **WIF Authentication**: Never store AWS credentials
7. **State Per Environment**: Separate AWS accounts = separate states
8. **Fail Fast**: Errors must surface immediately
9. **Examples Are Production**: No shortcuts, no placeholders
10. **Docs Match Code**: Every code change = doc update in SAME commit (ENFORCED)

**Remember**: These rules come from real production failures identified in senior engineer review. They exist to prevent you from repeating those mistakes.
```

---

### Module Architecture

```
agentcore-foundation → (Gateway, Identity, Observability)
    ↓
    ├─→ agentcore-tools → (Code Interpreter, Browser)
    ├─→ agentcore-runtime → (Runtime, Memory, Packaging)
    │       ↓
    │   agentcore-governance → (Policies, Evaluations)
```

**Dependency Rules**:
1. Foundation has NO dependencies
2. Tools depends on Foundation
3. Runtime depends on Foundation
4. Governance depends on Foundation + Runtime

### CLI-Based Resources

7 resources require AWS CLI (not in Terraform provider):
- Runtime (`bedrock-agentcore-control create-agent-runtime`)
- Memory (`bedrock-agentcore-control create-memory`)
- Policy Engine (`bedrock-agentcore-control create-policy-engine`)
- Cedar Policies (`bedrock-agentcore-control create-policy`)
- Evaluators (`bedrock-agentcore-control create-evaluator`)
- OAuth2 Providers (`bedrock-agentcore-control create-oauth2-credential-provider`)

**Pattern**:
```hcl
resource "null_resource" "resource_name" {
  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore-control create-X \
        --options \
        --output json > ${path.module}/.terraform/output.json
    EOT
  }
}

data "external" "resource_output" {
  program = ["cat", "${path.module}/.terraform/output.json"]
  depends_on = [null_resource.resource_name]
}
```

### Testing Strategy

**Local (NO AWS)**:
```bash
terraform fmt -check
terraform validate
terraform plan -backend=false
tflint
checkov
```

**CI Pipeline**:
1. validate → lint → test (no AWS)
2. deploy-dev (auto on main merge)
3. deploy-test (manual on release/*)
4. deploy-prod (manual on tags)

**Key Principle**: Developers NEVER need AWS for validation

### Common Tasks

#### Adding a New Variable
1. Add to module's `variables.tf` with validation
2. Add to root `variables.tf`
3. Add to `terraform.tfvars.example`
4. Update documentation in README.md
5. Add test case if needed

#### Adding a New Resource
1. Determine if Terraform-native or CLI-based
2. Add resource definition
3. Add corresponding outputs
4. Update module README
5. Run `terraform validate`
6. Run Checkov scan

#### Fixing Security Issues
1. Check senior engineer review (C:\Users\julia\.claude\plans\snoopy-watching-meerkat-agent-a6c207e.md)
2. Reference Phase 0 critical fixes
3. Test fix with Checkov: `checkov -d . --framework terraform`
4. Verify with terraform validate

#### Creating New Example
1. Create directory: `examples/N-name/`
2. Add agent-code/ subdirectory
3. Create runtime.py
4. Create terraform.tfvars
5. Test: `terraform plan -var-file=examples/N-name/terraform.tfvars`
6. Add to scripts/validate_examples.sh

### Migration Path

When AWS provider adds native resources:

```hcl
# BEFORE (CLI-based):
resource "null_resource" "runtime" {
  provisioner "local-exec" {
    command = "aws bedrock-agentcore-control create-agent-runtime ..."
  }
}

# AFTER (native):
resource "aws_bedrockagentcore_runtime" "main" {
  name     = var.agent_name
  role_arn = aws_iam_role.runtime.arn
  # Native attributes
}
```

Steps:
1. Import existing resource: `terraform import aws_bedrockagentcore_runtime.main <runtime-id>`
2. Replace null_resource with native resource
3. Update outputs
4. Test with terraform plan (should show no changes)
5. Remove .terraform/*.json files

### GitLab CI Variables Required

Configure in Settings → CI/CD → Variables:
- `CI_ENVIRONMENT_ROLE_ARN_DEV/TEST/PROD`: WIF role ARNs
- `TF_STATE_BUCKET_DEV/TEST/PROD`: S3 state buckets
- Optional: `SECRETS_PATH_DEV/TEST/PROD`: Secrets Manager paths

### File Organization

```
terraform/
├── modules/              # 4 core modules
├── examples/             # 3 example agents
├── tests/                # Test suite
├── docs/                 # Documentation + ADRs
├── scripts/              # Helper scripts
├── .gitlab-ci.yml        # CI/CD pipeline
└── [root TF files]       # Main orchestration
```

### When to Use Which Tool

**Read files**: `Read` tool (not `cat`)
**Search code**: `Grep` tool (not `grep`)
**Find files**: `Glob` tool (not `find`)
**Edit files**: `Edit` tool (not `sed`)
**Run Terraform**: `Bash` tool
**Search AWS docs**: Use terraform-mcp-server tools

### Before Committing

```bash
# Run locally
make test-validate
make test-security
pre-commit run --all-files

# Should pass:
terraform fmt -check
terraform validate
tflint
checkov (0 critical/high)
```

### Getting Help

1. Check this file (claude.md)
2. Check architecture.md
3. Check DEVELOPER_GUIDE.md
4. Check ADRs in docs/adr/
5. Check senior engineer review
6. Check plan file

### Key Decisions Summary

| Decision | Rationale | ADR | Status |
|----------|-----------|-----|--------|
| 4 modules | Clear separation | 0001 | Accepted |
| CLI-based | Provider gaps | 0002 | Accepted |
| GitLab CI | On-prem infra | 0003 | Accepted |
| S3 backend | Team collaboration | 0004 | Accepted |
| Hybrid secrets | Security + convenience | 0005 | Accepted |
| Separate backends (not workspaces) | Blast radius containment | 0006 | Accepted |
| Single region | Cost vs. complexity tradeoff | 0007 | Accepted |
| AWS-managed encryption | Simplicity, equivalent security | 0008 | Accepted |
| Agent discovery & identity | Service mesh, A2A auth | 0009 | **Proposed** |

### Version Info (PINNED per DevOps Review)

- Terraform: `1.5.7` (via `.terraform-version`)
- AWS Provider: `~> 5.30` (allows 5.30.x only)
- Python: 3.12 (for agent code)
- AWS CLI: >= 2.0
```

---

### docs/architecture.md - System Architecture

```markdown
# Bedrock AgentCore Terraform Architecture

## Document Status

| Aspect | Status |
|--------|--------|
| **Last Updated** | Phase 0 implementation |
| **Code Version** | Pre-fix (known issues documented below) |
| **Sync Status** | ✅ Matches current code state |

---

## ⚠️ Current State vs Planned State

### Current State (Pre-Phase 0)

**Status**: Contains 5 critical security issues identified in senior engineer review

| Issue ID | Location | Problem | Impact |
|----------|----------|---------|--------|
| SEC-001 | `iam.tf:46,54,94` | IAM wildcard `Resource = "*"` | Security audit failure |
| SEC-002 | `examples/*.tfvars` | Placeholder ARNs (123456789012) | Deployment failure |
| SEC-003 | `packaging.tf:96, runtime.tf:34` | Error suppression `\|\| true` | Silent failures |
| SEC-004 | `packaging.tf:57` | `head -20` limits deps | Missing packages |
| SEC-006 | `gateway.tf:77-82,130-135` | Dynamic block for simple attribute | Validation failure |

**Confirmed by file review**: `gateway.tf` lines 77-82 contain the exact SEC-006 bug.

### Planned State (Post-Phase 0)

After fixes are applied:
- ✅ All IAM policies use specific resource ARNs
- ✅ Variable validation rejects placeholder ARNs
- ✅ All provisioners fail fast on errors
- ✅ No arbitrary limits on dependencies
- ✅ Dynamic blocks only used for repeatable blocks
- ✅ Checkov scan returns zero critical/high issues

---

## System Overview

This Terraform implementation provisions AWS Bedrock AgentCore infrastructure for deploying AI agents.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     AgentCore Agent                      │
│                                                          │
│  ┌────────────┐  ┌──────────┐  ┌──────────────┐       │
│  │  Gateway   │  │  Runtime │  │ Code         │       │
│  │  (MCP)     │→ │          │→ │ Interpreter  │       │
│  └────────────┘  └──────────┘  └──────────────┘       │
│         │              │                                │
│         ↓              ↓                                │
│  ┌────────────┐  ┌──────────┐  ┌──────────────┐       │
│  │  Lambda    │  │  Memory  │  │  Browser     │       │
│  │  (MCP Tool)│  │  Store   │  │              │       │
│  └────────────┘  └──────────┘  └──────────────┘       │
│                                                          │
│         Monitored by CloudWatch + X-Ray                 │
│         Governed by Cedar Policies + Evaluators         │
└─────────────────────────────────────────────────────────┘
```

## Module Architecture

### 1. agentcore-foundation

**Purpose**: Core infrastructure (Gateway, Identity, Observability)

**Resources**:
- `aws_bedrockagentcore_gateway` - MCP protocol gateway
- `aws_bedrockagentcore_gateway_target` - MCP Lambda targets
- `aws_bedrockagentcore_workload_identity` - OAuth2 identity
- `aws_cloudwatch_log_group` - Centralized logging
- `aws_xray_sampling_rule` - Distributed tracing
- `aws_kms_key` - Encryption at rest

**Dependencies**: None (foundation layer)

### 2. agentcore-tools

**Purpose**: Agent capabilities (Code Interpreter, Browser)

**Resources**:
- `aws_bedrockagentcore_code_interpreter` - Python sandbox
- `aws_bedrockagentcore_browser` - Web browser
- CloudWatch log groups

**Dependencies**: Foundation (KMS key)

### 3. agentcore-runtime

**Purpose**: Execution + state (Runtime, Memory, Packaging)

**Resources**:
- `null_resource` + CLI for Runtime
- `null_resource` + CLI for Memory
- `aws_s3_bucket` - Deployment artifacts
- Two-stage build (dependencies → code)

**Dependencies**: Foundation (IAM roles)

### 4. agentcore-governance

**Purpose**: Security + quality (Policies, Evaluations)

**Resources**:
- `null_resource` + CLI for Policy Engine
- `null_resource` + CLI for Cedar Policies
- `null_resource` + CLI for Evaluators
- CloudWatch alarms

**Dependencies**: Foundation + Runtime

## Data Flow

### Agent Invocation Flow

```
1. External System → Gateway (MCP endpoint)
2. Gateway → Authenticates via Workload Identity
3. Gateway → Routes to Lambda (MCP target)
4. Lambda → Returns tool result
5. Gateway → Passes to Runtime
6. Runtime → Executes agent code
7. Agent Code → Uses Code Interpreter/Browser
8. Runtime → Stores state in Memory
9. Evaluator → Assesses response quality
10. Policy Engine → Enforces access controls
11. CloudWatch/X-Ray → Records metrics
12. Gateway → Returns response
```

### Deployment Flow

```
1. Developer → Commits code to Git
2. GitLab CI → Runs validate/lint/test (no AWS)
3. Merge to main → Auto-deploys to dev
4. Release branch → Manual deploy to test
5. Tag release → Manual deploy to prod
```

## Network Architecture

### Network Modes

**PUBLIC** (internet-facing):
- Code Interpreter/Browser connect to internet
- No VPC required
- Simple, lowest cost

**SANDBOX** (isolated):
- Code Interpreter/Browser in AWS managed network
- No internet access
- Balanced security/cost

**VPC** (customer VPC):
- Code Interpreter/Browser in your VPC
- Full network control
- VPC endpoints recommended

## Security Architecture

### Authentication & Authorization

```
GitLab → WIF → AWS STS → Temporary Credentials
    ↓
Terraform → Creates Resources
    ↓
Agent Runtime → IAM Role (least privilege)
    ↓
Gateway → Workload Identity (OAuth2)
    ↓
MCP Tools → Lambda IAM execution role
```

### Encryption

**At Rest**:
- S3: KMS or AES256
- CloudWatch: KMS (optional)
- Secrets Manager: KMS (default)

**In Transit**:
- All APIs use HTTPS/TLS
- Internal: AWS PrivateLink

### Policy Enforcement

```
Request → Policy Engine (Cedar) → Allow/Deny
    ↓
If Allowed → Runtime Executes
    ↓
Response → Evaluator → Quality Score
    ↓
Metrics → CloudWatch
```

## State Management

### Terraform State

```
S3 Bucket (per environment)
├── terraform.tfstate (current)
├── .terraform.tfstate.backup
└── [versioned snapshots]

DynamoDB Table (per environment)
├── LockID (partition key)
└── [lock records]
```

### Agent State

**Short-term Memory**:
- In-memory storage
- TTL: configurable (default 60 min)
- Use: conversation context

**Long-term Memory**:
- Persistent storage (S3-backed)
- Infinite retention
- Use: learned knowledge

## Observability

### Metrics (CloudWatch)

- **Gateway**: Invocations, errors, latency
- **Runtime**: Executions, memory usage
- **Tools**: Code interpreter runs, browser sessions
- **Evaluations**: Quality scores, pass/fail rates

### Logs (CloudWatch Logs)

```
/aws/bedrock/agentcore/
├── gateway/{agent-name}
├── runtime/{agent-name}
├── code-interpreter/{agent-name}
├── browser/{agent-name}
├── policy-engine/{agent-name}
└── evaluator/{agent-name}
```

### Tracing (X-Ray)

- End-to-end request tracing
- Service map visualization
- Latency analysis
- Error tracking

## Cost Architecture

### Cost Drivers

| Component | Cost Model | Estimate |
|-----------|------------|----------|
| Gateway | Per request | $0.001/request |
| Runtime | Per execution | $0.01/execution |
| Code Interpreter | Per second | $0.001/second |
| Browser | Per session | $0.01/session |
| Memory | Per GB-month | $0.023/GB-month |
| S3 Storage | Per GB-month | $0.023/GB-month |
| CloudWatch Logs | Per GB ingested | $0.50/GB |

**Typical Agent Cost**: $10-50/month (low volume)

## Scaling Architecture

### Horizontal Scaling

- Gateway: Auto-scales with load
- Runtime: Concurrent executions (1000s)
- Tools: Independent scaling

### Vertical Scaling

- Runtime: Configurable memory/CPU
- Code Interpreter: Timeout configuration
- Browser: Session limits

## Disaster Recovery

### Backup Strategy

- **Terraform State**: S3 versioning (90 days)
- **Agent Code**: Git repository
- **Long-term Memory**: S3 versioning
- **Configuration**: GitLab backup

### Recovery Procedures

1. **State Corruption**: Restore from S3 version
2. **Resource Deletion**: `terraform import` + `terraform apply`
3. **Code Loss**: Git clone + redeploy
4. **Account Compromise**: Rotate WIF credentials

## Deployment Environments

| Environment | Purpose | Promotion | Auto-Deploy |
|-------------|---------|-----------|-------------|
| Dev | Development | main branch | Yes |
| Test | Integration testing | release/* | Manual |
| Prod | Production | v* tags | Manual |

## Integration Points

### External Systems

- **MCP Tools**: Lambda functions (your code)
- **Secrets Manager**: Runtime secrets
- **GitHub**: Source code (initially)
- **GitLab**: CI/CD + source (target)
- **AWS Accounts**: Separate per environment

### APIs

- **Bedrock AgentCore**: AWS service APIs
- **S3**: Storage APIs
- **CloudWatch**: Monitoring APIs
- **Secrets Manager**: Secret retrieval
```

---

### README.md - User Documentation (Matching DeepResearch Quality)

**Location**: `terraform/README.md` (project root)

**Quality Benchmark**: Must match or exceed [deepagents-bedrock-agentcore-terraform/README.md](../deepagents-bedrock-agentcore-terraform/README.md)

```markdown
# AWS Bedrock AgentCore Terraform

A production-ready, modular Terraform implementation for deploying AI agents on AWS Bedrock AgentCore.

## Overview

This project provides a complete infrastructure-as-code solution for:

- Deploying AI agents with MCP protocol support
- Code interpretation and web browsing capabilities
- Agent memory (short-term and long-term)
- Cedar policy-based access control
- Quality evaluation and monitoring
- Multi-environment deployment (dev/test/prod)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   AgentCore Agent                        │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐        │
│  │ Gateway  │→ │ Runtime  │→ │ Code Interpreter│        │
│  │  (MCP)   │  │          │  │    / Browser    │        │
│  └──────────┘  └──────────┘  └────────────────┘        │
│       │             │                                    │
│       ↓             ↓                                    │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐        │
│  │  Lambda  │  │  Memory  │  │   Evaluator    │        │
│  │(MCP Tool)│  │          │  │                │        │
│  └──────────┘  └──────────┘  └────────────────┘        │
│                                                          │
│         Monitored by CloudWatch + X-Ray                  │
│         Governed by Cedar Policies                       │
└──────────────────────────────────────────────────────────┘
```

## Project Structure

```
terraform/
├── modules/
│   ├── agentcore-foundation/   # Gateway, Identity, Observability
│   ├── agentcore-tools/        # Code Interpreter, Browser
│   ├── agentcore-runtime/      # Runtime, Memory, Packaging
│   └── agentcore-governance/   # Policies, Evaluations
├── examples/
│   ├── 1-hello-world/          # Basic S3 explorer agent
│   ├── 2-gateway-tool/         # MCP tool with Titanic analysis
│   └── 3-deepresearch/         # Full research agent
├── docs/
│   ├── adr/                    # Architecture Decision Records
│   └── architecture.md         # System architecture
├── main.tf                     # Module composition
├── variables.tf                # Input variables
├── CLAUDE.md                   # AI agent development rules
└── DEVELOPER_GUIDE.md          # Team onboarding
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials
- Python 3.12+ (for agent code)
- Access to AWS Bedrock AgentCore

## Quick Start

### 1. Clone and Initialize

```bash
git clone <repository-url>
cd terraform
terraform init
```

### 2. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Validate

```bash
terraform validate
terraform plan
```

### 4. Deploy

```bash
terraform apply
```

### 5. Verify

```bash
terraform output
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

## Terraform Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `agent_name` | Unique name for the agent |
| `region` | AWS region for deployment |
| `runtime_source_path` | Path to agent source code |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `dev` | Environment name (dev/test/prod) |
| `enable_gateway` | `true` | Enable MCP gateway |
| `enable_code_interpreter` | `true` | Enable Python sandbox |
| `enable_browser` | `false` | Enable web browsing |
| `enable_memory` | `true` | Enable agent memory |
| `code_interpreter_network_mode` | `SANDBOX` | Network mode (PUBLIC/SANDBOX/VPC) |
| `log_retention_days` | `30` | CloudWatch log retention |

### Example terraform.tfvars

```hcl
agent_name          = "my-research-agent"
region              = "us-east-1"
environment         = "dev"
runtime_source_path = "./agent-code"

enable_gateway          = true
enable_code_interpreter = true
enable_memory           = true

mcp_targets = {
  search = {
    name       = "web-search"
    lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:search-mcp"
  }
}

tags = {
  Project = "research-agent"
  Owner   = "team@example.com"
}
```

## Examples

### Hello World (S3 Explorer)

```bash
terraform apply -var-file=examples/1-hello-world/terraform.tfvars
```

Basic agent that lists S3 buckets. Demonstrates minimal configuration.

### Gateway Tool (Titanic Analysis)

```bash
terraform apply -var-file=examples/2-gateway-tool/terraform.tfvars
```

Agent with MCP gateway calling Lambda tool to analyze Titanic dataset.

### Deep Research Agent

```bash
terraform apply -var-file=examples/3-deepresearch/terraform.tfvars
```

Full-featured research agent with web browsing, code interpreter, and memory.

## Local Development

### Validate Without AWS

```bash
# All these run locally, no AWS account needed:
terraform fmt -check
terraform validate
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars
checkov -d . --framework terraform
tflint
```

### Run Agent Locally

```bash
cd examples/1-hello-world/agent-code
python runtime.py
```

## Monitoring

### CloudWatch Logs

```bash
# Gateway logs
aws logs tail /aws/bedrock/agentcore/gateway/<agent-name> --follow

# Runtime logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

### CloudWatch Alarms

Pre-configured alarms for:
- Gateway error rate
- Runtime failures
- Evaluation quality drops

## Cost Considerations

| Component | Cost Model | Estimate |
|-----------|------------|----------|
| Gateway | Per request | $0.001/request |
| Runtime | Per execution | $0.01/execution |
| Code Interpreter | Per second | $0.001/second |
| Memory | Per GB-month | $0.023/GB-month |
| CloudWatch Logs | Per GB | $0.50/GB |

**Typical Agent Cost**: $10-50/month (low volume)

## Security

- KMS encryption at rest (optional)
- IAM least privilege roles
- Cedar policy enforcement
- VPC isolation support
- No credentials in code (WIF for CI/CD)

## Cleanup

```bash
terraform destroy
```

## Documentation

- [Architecture](docs/architecture.md) - System design
- [Developer Guide](DEVELOPER_GUIDE.md) - Team onboarding
- [AI Agent Rules](CLAUDE.md) - Development principles
- [ADRs](docs/adr/) - Architecture decisions

## License

See LICENSE file.
```

---

### DEVELOPER_GUIDE.md - Team Onboarding

```markdown
# Developer Guide - Bedrock AgentCore Terraform

## Welcome!

This guide will get you from zero to deploying agents in < 30 minutes.

## Prerequisites

### Required
- [x] Git installed
- [x] Terraform >= 1.5.0
- [x] AWS CLI configured
- [x] Python 3.12+
- [x] Text editor (VS Code recommended)

### Optional
- [ ] Docker (for local testing)
- [ ] Go 1.20+ (for Terratest)
- [ ] pre-commit (`pip install pre-commit`)

## Quick Start (5 Minutes)

```bash
# 1. Clone repository
git clone <repo-url>
cd terraform

# 2. Install pre-commit hooks
pre-commit install

# 3. Validate everything works
terraform init -backend=false
terraform validate
terraform fmt -check

# 4. Run security scan
checkov -d .

# 5. Test with example
terraform plan -var-file=examples/1-hello-world/terraform.tfvars
```

If all commands succeed, you're ready to develop!

## Development Workflow

### Making Changes

```bash
# 1. Create feature branch
git checkout -b feature/add-new-module

# 2. Make your changes
# Edit files...

# 3. Validate locally (NO AWS needed)
make test-validate      # fmt + validate + plan
make test-security      # tflint + checkov

# 4. Commit (pre-commit hooks run automatically)
git add .
git commit -m "feat: add new module"

# 5. Push and create MR
git push origin feature/add-new-module
```

### Local Testing (No AWS Required)

```bash
# Format check
terraform fmt -check -recursive

# Syntax validation
terraform validate

# Generate plan (dry-run)
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars

# Security scan
checkov -d . --framework terraform --quiet

# Lint
tflint --recursive

# All tests
make test-all
```

**Key Point**: You can validate everything locally without an AWS account!

## Project Structure

```
terraform/
├── modules/              # Core modules (DON'T directly edit in dev)
│   ├── agentcore-foundation/
│   ├── agentcore-tools/
│   ├── agentcore-runtime/
│   └── agentcore-governance/
│
├── examples/             # Example agents (EDIT these for learning)
│   ├── 1-hello-world/
│   ├── 2-gateway-tool/
│   └── 3-deepresearch/
│
├── tests/                # Test suite
│   ├── validation/
│   ├── security/
│   └── unit/
│
├── docs/                 # Documentation
│   ├── adr/              # Architecture decisions
│   └── architecture.md   # System architecture
│
├── scripts/              # Helper scripts
│   ├── validate_examples.sh
│   ├── setup_backend.sh
│   └── deploy.sh
│
├── main.tf               # Module composition
├── variables.tf          # Input variables
├── outputs.tf            # Output values
├── .gitlab-ci.yml        # CI/CD pipeline
├── CLAUDE.md             # AI agent rules (auto-loaded)
├── DEVELOPER_GUIDE.md    # Developer onboarding
└── README.md             # User documentation
```

## Common Tasks

### Task 1: Create a New Example Agent

```bash
# 1. Create directory
mkdir -p examples/4-my-agent/agent-code

# 2. Create agent code
cat > examples/4-my-agent/agent-code/runtime.py <<'EOF'
def handler(event, context):
    return {"status": "success", "message": "Hello!"}
EOF

# 3. Create Terraform config
cat > examples/4-my-agent/terraform.tfvars <<'EOF'
agent_name          = "my-agent"
region              = "us-east-1"
environment         = "dev"

enable_gateway      = false
enable_runtime      = true
runtime_source_path = "./examples/4-my-agent/agent-code"

enable_observability = true
EOF

# 4. Test it
terraform plan -var-file=examples/4-my-agent/terraform.tfvars
```

### Task 2: Add a New Variable

```bash
# 1. Add to module's variables.tf
# modules/agentcore-foundation/variables.tf
variable "my_new_setting" {
  description = "Description here"
  type        = string
  default     = "default-value"

  validation {
    condition     = length(var.my_new_setting) > 0
    error_message = "Value must not be empty."
  }
}

# 2. Use in module resource
# modules/agentcore-foundation/gateway.tf
resource "aws_bedrockagentcore_gateway" "main" {
  name = var.my_new_setting
  # ...
}

# 3. Add to root variables.tf
variable "my_new_setting" {
  description = "Description here"
  type        = string
  default     = "default-value"
}

# 4. Pass to module in main.tf
module "agentcore_foundation" {
  source = "./modules/agentcore-foundation"

  my_new_setting = var.my_new_setting
  # ...
}

# 5. Add to examples
# examples/1-hello-world/terraform.tfvars
my_new_setting = "custom-value"

# 6. Test
terraform validate
```

### Task 3: Fix Security Issue

```bash
# 1. Run Checkov to identify issues
checkov -d . --framework terraform

# 2. Review findings
# Example: "Resource uses wildcard in IAM policy"

# 3. Fix the issue
# BEFORE:
Resource = "*"

# AFTER:
Resource = [
  "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
]

# 4. Re-run Checkov
checkov -d . --framework terraform

# 5. Verify fix
terraform validate
terraform plan
```

### Task 4: Add a New Resource

```bash
# 1. Determine if Terraform-native or CLI-based
# Check: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

# If Terraform-native:
resource "aws_bedrockagentcore_new_resource" "main" {
  name     = var.agent_name
  # ...
}

# If CLI-based:
resource "null_resource" "new_resource" {
  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore-control create-new-resource \
        --name ${var.agent_name} \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/new_resource.json
    EOT
  }
}

data "external" "new_resource_output" {
  program = ["cat", "${path.module}/.terraform/new_resource.json"]
  depends_on = [null_resource.new_resource]
}

# 2. Add outputs
output "new_resource_id" {
  value = data.external.new_resource_output.result.resourceId
}

# 3. Test
terraform validate
```

## Testing Your Changes

### Level 1: Local Validation (Always Run)

```bash
# Quick validation (30 seconds)
terraform fmt -check
terraform validate
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars
```

### Level 2: Security Scan (Before Commit)

```bash
# Security check (1 minute)
checkov -d . --framework terraform --quiet
tflint --recursive
```

### Level 3: Full Test Suite (Optional)

```bash
# Complete tests (5 minutes)
make test-all

# Or individually:
make test-validate
make test-security
make test-examples
```

### Level 4: Deploy to Dev (After MR Approved)

Automatic via GitLab CI when merged to `main`.

## Debugging

### Common Issues

#### "terraform: command not found"
```bash
# Install Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads
```

#### "Error: Module not found"
```bash
# Initialize Terraform
terraform init
```

#### "Checkov failed with critical issues"
```bash
# See detailed output
checkov -d . --framework terraform

# Fix issues, then re-run
```

#### "Pre-commit hooks failing"
```bash
# Run manually to see errors
pre-commit run --all-files

# Fix issues, then retry commit
```

### Getting Help

1. Check CLAUDE.md (AI assistant guide)
2. Check docs/architecture.md (system design)
3. Check docs/adr/ (design decisions)
4. Check IMPLEMENTATION_SUMMARY.md
5. Ask in team chat
6. Create GitLab issue

## GitLab CI Pipeline

### Pipeline Stages

```
validate → lint → test → deploy-dev → deploy-test → deploy-prod
  (auto)   (auto) (auto)   (auto)      (manual)      (manual)
```

### Triggering Deployments

**Dev**: Automatic on merge to `main`
```bash
git checkout main
git merge feature/my-branch
git push origin main
# → CI deploys to dev automatically
```

**Test**: Manual from release branch
```bash
git checkout -b release/v1.2.0
git push origin release/v1.2.0
# → Go to GitLab, trigger deploy-test job manually
```

**Prod**: Manual from tag
```bash
git tag v1.2.0
git push origin v1.2.0
# → Go to GitLab, trigger deploy-prod job manually (requires approval)
```

## Best Practices

### DO
- ✅ Run `make test-validate` before every commit
- ✅ Use pre-commit hooks
- ✅ Test examples after module changes
- ✅ Add validation to variables
- ✅ Use descriptive commit messages
- ✅ Keep changes focused (one feature per MR)
- ✅ Document decisions in ADRs

### DON'T
- ❌ Use `Resource = "*"` in IAM policies
- ❌ Suppress errors with `|| true`
- ❌ Skip validation before pushing
- ❌ Commit directly to main (use MRs)
- ❌ Use placeholder ARNs (123456789012)
- ❌ Make changes without running Checkov
- ❌ Forget to update documentation

## Cheat Sheet

```bash
# Validate everything
make test-all

# Format code
terraform fmt -recursive

# Security scan
checkov -d .

# Test example
terraform plan -var-file=examples/1-hello-world/terraform.tfvars

# View state
terraform state list

# See module outputs
terraform output

# Clean up
terraform destroy

# Get help
terraform --help
make help
```

## Next Steps

1. ✅ Complete quick start
2. ✅ Read CLAUDE.md
3. ✅ Review examples/
4. ✅ Try modifying examples/1-hello-world
5. ✅ Create your first MR
6. ✅ Deploy to dev

Welcome to the team! 🚀
```

---

## APPENDIX B: DEVOPS REVIEW SUMMARY

### Issues Identified: 25 Total

| Category | Count | Priority | Examples |
|----------|-------|----------|----------|
| Deployment Safety | 5 | HIGH | No rollback testing, PowerUserAccess too broad |
| Version Management | 4 | MEDIUM | No .terraform-version, provider constraints too loose |
| Disaster Recovery | 4 | MEDIUM | Single region, no state backup verification |
| Observability Gaps | 4 | MEDIUM | Alert fatigue, no SLAs, no dashboard |
| Security Hardening | 4 | MEDIUM | KMS policy too broad, no secrets rotation |
| Missing Documentation | 4 | LOW | No network diagram, no runbooks |

### New Items Added to Plan

**Phase 0 (now ~10 hours, was 8)**:
- SEC-007: Scope KMS key policy
- SEC-008: Replace PowerUserAccess with scoped policy
- SEC-009: Add `sensitive = true` to outputs
- Add `.terraform-version` file
- Pin AWS provider to `~> 5.30`

**Phase 1 (additional deliverables)**:
- `docs/adr/0006-separate-backends-not-workspaces.md`
- `docs/adr/0007-single-region-decision.md`
- `docs/runbooks/` directory with 3 runbooks
- `.terraform-version` file

**Phase 5 (additional tasks)**:
- Test rollback procedure in dev
- Add drift detection scheduled job
- Create CloudWatch dashboard
- Define SLOs and alert tiers

### Edge Cases to Test

| Scenario | Expected Behavior |
|----------|-------------------|
| Lambda ARN doesn't exist | Clear error message, deployment fails |
| S3 bucket name conflict | Terraform import guidance in error |
| KMS key deleted externally | Fail with decrypt error, documented recovery |
| Empty agent source path | Fail fast, not silent empty zip |
| DynamoDB lock timeout | Retry logic with exponential backoff |
| WIF token expires mid-deploy | Resume procedure documented |

### Revised Timeline

| Phase | Original | Updated | Change |
|-------|----------|---------|--------|
| Phase 0 | 1-2 days | 1.5-2 days | +2 hours for SEC-007/008/009 |
| Phase 1 | 2-3 days | 3 days | +0.5 day for runbooks/ADRs |
| Phase 5 | 4-5 days | 5-6 days | +1 day for dashboards/SLOs |
| **MVP Total** | 9-13 days | 11-15 days | +2-3 days |

### Review Status

- [x] Critical security issues (5) → Phase 0
- [x] Additional security issues (4) → Phase 0 expanded
- [x] Version management → Phase 0/1
- [x] Disaster recovery → Phase 1/5
- [x] Observability gaps → Phase 5
- [x] Edge case testing → Integration tests
- [x] Documentation gaps → Phase 1

**DevOps Review Complete**: Plan updated with all findings.

---

**Last Updated**: Senior DevOps Review Complete
**Reviewer**: Claude Opus 4.5 (Senior DevOps Perspective)
**Plan Version**: 2.0 (with DevOps findings integrated)
