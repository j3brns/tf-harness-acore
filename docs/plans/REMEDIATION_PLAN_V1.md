# Remediation Plan V1: Critical Architectural Defects

## Status
Resolved

## Context
A deep architectural review using `codebase_investigator` identified three critical defects that render the current Terraform codebase unfit for production CI/CD. These issues have been remediated across all core modules.

## 1. The "Ephemeral State" Defect (Blocker)

### Problem
Current provisioning scripts store resource IDs (e.g., `agent_id`) in local JSON files inside `.terraform/`.
- **Failure Mode:** CI/CD runners (GitHub Actions/GitLab CI) wipe this directory after every run.
- **Consequence:** Subsequent runs fail to find IDs, causing Terraform to attempt re-creation (duplicate error) or lose track of resources entirely.

### Solution: The "SSM Persistence" Pattern
We will replace local file storage with **AWS Systems Manager Parameter Store**.

**New Workflow:**
1.  **Create:** `local-exec` calls `create-agent`.
2.  **Persist:** `local-exec` calls `aws ssm put-parameter --name "/bedrock/agents/${name}/id" --value $ID`.
3.  **Read:** Terraform uses `data "aws_ssm_parameter"` to retrieve the ID for other resources.

**Benefit:** State is persistent, queryable, and survives CI runner destruction.

---

## 2. The "Ghost Resource" Defect (High Severity)

### Problem
`null_resource` blocks have create logic but **zero destroy logic**.
- **Failure Mode:** `terraform destroy` removes the state file entry but leaves the AWS Bedrock resources running.
- **Consequence:** Massive "zombie" resource accumulation and hidden costs.

### Solution: Lifecycle Management Hooks
We will add `when = destroy` provisioners to every `null_resource`.

**New Workflow:**
1.  **Trigger:** `terraform destroy` fires.
2.  **Lookup:** Provisioner reads the ID from SSM (via `self.triggers` or direct fetch).
3.  **Teardown:** `aws bedrock delete-agent ...`
4.  **Cleanup:** `aws ssm delete-parameter ...`

---

## 3. The "Lateral Movement" Defect (High Security Risk)

### Problem
The Workload Identity role uses a wildcard trust: `arn:aws:iam::...:role/agentcore-*`.
- **Failure Mode:** Any compromised agent can assume the identity of *any other* agent in the system.
- **Consequence:** Violation of Zero Trust; enables lateral movement between sensitive and non-sensitive agents.

### Solution: ABAC Scoping
We will replace name-based wildcards with **Attribute-Based Access Control (ABAC)**.
- **Policy:** `Condition: StringEquals: aws:PrincipalTag/Project = ${aws:ResourceTag/Project}`.
- **Effect:** An agent can only assume roles that belong to its specific security domain.

---

## 4. Native Migration Strategy (Backing out the Hack)

When the `hashicorp/aws` provider eventually adds native support for `aws_bedrockagent_agent` (etc.), we will migrate without downtime.

### The Migration Playbook

1.  **Identify:** Updates to `versions.tf` show new resource support.
2.  **Import:** Run `terraform import aws_bedrockagent_agent.main <ID_FROM_SSM>`.
    *   *Crucial:* We have the ID in SSM, so we don't need to hunt for it.
3.  **Refactor:**
    *   Comment out the `null_resource`.
    *   Define the native `resource "aws_bedrockagent_agent"`.
    *   Point outputs to the new native resource attributes.
4.  **Cleanup:**
    *   Run `terraform apply`. State updates to use the native API.
    *   Manually delete the SSM parameter (or let a cleanup script do it).

**Why this works:** The actual AWS resource ID (e.g., `AGENT-12345`) never changes. We just swap the *manager* from `null_resource` (shell script) to `provider` (Go code).
