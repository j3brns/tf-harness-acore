# Bedrock AgentCore Terraform Architecture

## Document Status

| Aspect | Status |
|--------|--------|
| **Last Updated** | Phase 0 implementation complete |
| **Code Version** | Post-security fixes |
| **Sync Status** | Matches current code state |

---

## System Overview

This Terraform implementation provisions AWS Bedrock AgentCore infrastructure for deploying AI agents with MCP protocol support, code interpretation, web browsing, memory, and governance capabilities.

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
│   ├── 2-gateway-tool/         # MCP gateway with Titanic analysis
│   ├── 3-deepresearch/         # Full Strands DeepAgents implementation
│   ├── 4-research/             # Simplified research agent
│   ├── 5-integrated/           # Module composition (RECOMMENDED)
│   └── mcp-servers/            # Lambda MCP servers + local dev
├── docs/
│   ├── adr/                    # Architecture Decision Records
│   ├── runbooks/               # Operational runbooks
│   └── architecture.md         # This file
├── tests/
│   ├── validation/             # Terraform validation scripts
│   └── security/               # Security scanning scripts
├── scripts/                    # Helper utilities
├── main.tf                     # Module composition
├── variables.tf                # Root variables
├── outputs.tf                  # Root outputs
├── versions.tf                 # Provider configuration
├── CLAUDE.md                   # AI development rules
├── DEVELOPER_GUIDE.md          # Team onboarding
└── README.md                   # User documentation
```

## High-Level Architecture

```
+-------------------------------------------------------------+
|                     AgentCore Agent                          |
|                                                              |
|  +------------+  +----------+  +--------------+             |
|  |  Gateway   |->| Runtime  |->| Code         |             |
|  |  (MCP)     |  |          |  | Interpreter  |             |
|  +------------+  +----------+  +--------------+             |
|        |              |                                      |
|        v              v                                      |
|  +------------+  +----------+  +--------------+             |
|  |  Lambda    |  |  Memory  |  |   Browser    |             |
|  | (MCP Tool) |  |          |  |              |             |
|  +------------+  +----------+  +--------------+             |
|                                                              |
|         Monitored by CloudWatch + X-Ray                      |
|         Governed by Cedar Policies + Evaluators              |
+-------------------------------------------------------------+
```

## Module Architecture

### Dependency Graph

```
agentcore-foundation (NO dependencies)
        |
        +---> agentcore-tools (depends: foundation)
        +---> agentcore-runtime (depends: foundation)
                    |
                agentcore-governance (depends: foundation + runtime)
```

### 1. agentcore-foundation

**Purpose**: Core infrastructure (Gateway, Identity, Observability)

**Resources**:
- `null_resource` + CLI for Gateway (MCP protocol gateway)
- `null_resource` + CLI for Gateway Target (MCP Lambda targets)
- `null_resource` + CLI for Workload Identity (OAuth2 identity)
- `aws_cloudwatch_log_group` - Centralized logging
- `aws_xray_sampling_rule` - Distributed tracing
- IAM roles and policies

**Encryption**: AWS-managed (SSE-S3, default CloudWatch encryption)

**Dependencies**: None (foundation layer)

### 2. agentcore-tools

**Purpose**: Agent capabilities (Code Interpreter, Browser)

**Resources**:
- `null_resource` + CLI for Code Interpreter (Python sandbox)
- `null_resource` + CLI for Browser (Web browser)
- CloudWatch log groups
- IAM roles

**Network Modes**: PUBLIC, SANDBOX, VPC

**Dependencies**: Foundation (for observability integration)

### 3. agentcore-runtime

**Purpose**: Execution + state (Runtime, Memory, Packaging)

**Resources**:
- `null_resource` + CLI for Runtime
- `null_resource` + CLI for Memory
- `aws_s3_bucket` - Deployment artifacts
- Two-stage build (dependencies -> code)

**Encryption**: AWS-managed (SSE-S3/AES256)

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
1. External System -> Gateway (MCP endpoint)
2. Gateway -> Authenticates via Workload Identity
3. Gateway -> Routes to Lambda (MCP target)
4. Lambda -> Returns tool result
5. Gateway -> Passes to Runtime
6. Runtime -> Executes agent code
7. Agent Code -> Uses Code Interpreter/Browser
8. Runtime -> Stores state in Memory
9. Evaluator -> Assesses response quality
10. Policy Engine -> Enforces access controls
11. CloudWatch/X-Ray -> Records metrics
12. Gateway -> Returns response
```

### Deployment Flow

```
1. Developer -> Commits code to Git
2. GitLab CI -> Runs validate/lint/test (no AWS)
3. Merge to main -> Auto-deploys to dev
4. Release branch -> Manual deploy to test
5. Tag release -> Manual deploy to prod
```

## Security Architecture

### Authentication & Authorization

```
GitLab -> WIF -> AWS STS -> Temporary Credentials
    |
    v
Terraform -> Creates Resources
    |
    v
Agent Runtime -> IAM Role (least privilege)
    |
    v
Gateway -> Workload Identity (OAuth2)
    |
    v
MCP Tools -> Lambda IAM execution role
```

### Encryption Strategy (ADR 0008)

**At Rest**:
- S3: AWS-managed SSE-S3 (AES256)
- CloudWatch: AWS-managed encryption
- Secrets Manager: AWS-managed KMS (default)

**In Transit**:
- All APIs use HTTPS/TLS
- Internal: AWS PrivateLink (when VPC mode enabled)

**Rationale**: AWS-managed encryption provides equivalent security with less operational overhead. See `docs/adr/0008-aws-managed-encryption.md`.

### Policy Enforcement

```
Request -> Policy Engine (Cedar) -> Allow/Deny
    |
    v
If Allowed -> Runtime Executes
    |
    v
Response -> Evaluator -> Quality Score
    |
    v
Metrics -> CloudWatch
```

## State Management

### Terraform State (ADR 0004)

Using S3 backend with **native S3 locking** (Terraform 1.10.0+):

```
S3 Bucket (per environment)
├── agentcore/
│   ├── terraform.tfstate        (current state)
│   ├── terraform.tfstate.tflock (lock file during operations)
│   └── [versioned snapshots]    (via S3 versioning)
```

**Note**: DynamoDB-based locking is deprecated. Native S3 locking via `use_lockfile = true` is the recommended approach.

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
+-- gateway/{agent-name}
+-- runtime/{agent-name}
+-- code-interpreter/{agent-name}
+-- browser/{agent-name}
+-- policy-engine/{agent-name}
+-- evaluator/{agent-name}
```

### Tracing (X-Ray)

- End-to-end request tracing
- Service map visualization
- Latency analysis
- Error tracking

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
- **GitHub/GitLab**: Source code + CI/CD
- **AWS Accounts**: Separate per environment

### APIs

- **Bedrock AgentCore**: AWS service APIs
- **S3**: Storage APIs
- **CloudWatch**: Monitoring APIs
- **Secrets Manager**: Secret retrieval

## CLI-Based Resources

Due to AWS provider gaps, the core Bedrock AgentCore suite uses AWS CLI:

| Resource | CLI Command |
|----------|------------|
| Gateway | `bedrock-agentcore-control create-gateway` |
| Identity | `bedrock-agentcore-control create-workload-identity` |
| Browser | `bedrock-agentcore-control create-browser` |
| Code Interpreter | `bedrock-agentcore-control create-code-interpreter` |
| Runtime | `bedrock-agentcore-control create-agent-runtime` |
| Memory | `bedrock-agentcore-control create-memory` |
| Policy Engine | `bedrock-agentcore-control create-policy-engine` |
| Cedar Policies | `bedrock-agentcore-control create-policy` |
| Evaluators | `bedrock-agentcore-control create-evaluator` |
| OAuth2 Providers | `bedrock-agentcore-control create-oauth2-credential-provider` |

See `docs/adr/0002-cli-based-resources.md` for migration path when native resources become available.

## Architecture Decision Records

| ADR | Decision |
|-----|----------|
| 0001 | Four-module architecture |
| 0002 | CLI-based resources via null_resource |
| 0003 | GitLab CI with WIF authentication |
| 0004 | S3 backend with native S3 locking |
| 0005 | Hybrid secrets management |
| 0006 | Separate backends (not workspaces) |
| 0007 | Single region deployment |
| 0008 | AWS-managed encryption |

See `docs/adr/` for full decision records.
