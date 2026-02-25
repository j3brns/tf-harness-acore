# Policy Conformance Report
*Generated on: 2026-02-25 14:02:46*

## Executive Summary
**Overall Status**: ✅ COMPLIANT

### Inventory Summary
| Exception Type | Count | Expected | Status |
|----------------|-------|----------|--------|
| ec2_network_interface | 2 | 2 | ✅ |
| logs_put_resource_policy | 1 | 1 | ✅ |
| bedrock_abac_scoped | 1 | 1 | ✅ |
| s3_list_all_my_buckets | 1 | 1 | ✅ |

## Detailed IAM Wildcard Inventory
| File | Line | Classification | Rationale | Status |
|------|------|----------------|-----------|--------|
| `terraform/modules/agentcore-foundation/gateway.tf` | 103 | logs_put_resource_policy | AWS-REQUIRED: logs:PutResourcePolicy does not support resource-level scoping | ✅ |
| `terraform/modules/agentcore-foundation/iam.tf` | 193 | bedrock_abac_scoped | Rule 14.3 ABAC: StringEqualsIfExists is required because AWS-managed resources | ✅ |
| `terraform/modules/agentcore-tools/iam.tf` | 81 | ec2_network_interface | AWS-REQUIRED: EC2 network interface APIs do not support resource-level scoping. | ✅ |
| `terraform/modules/agentcore-tools/iam.tf` | 173 | ec2_network_interface | AWS-REQUIRED: EC2 network interface APIs do not support resource-level scoping. | ✅ |
| `examples/mcp-servers/terraform/main.tf` | 229 | s3_list_all_my_buckets | AWS-REQUIRED: s3:ListAllMyBuckets does not support resource-level scoping | ✅ |

## Tag Taxonomy Conformance
Standardized tags: `AppID`, `Environment`, `AgentName`, `ManagedBy`, `Owner`.

| Check | Status | Details |
|-------|--------|---------|
| `locals.tf` canonical_tags | PASS | AppID: ✅, Environment: ✅, AgentName: ✅, ManagedBy: ✅, Owner: ✅ |
| `versions.tf` default_tags | PASS | AppID: ✅, Environment: ✅, AgentName: ✅, ManagedBy: ✅, Owner: ✅ |

---
*Note: This report is automatically generated. Any deviations must be approved via the Exception Change Control process documented in GEMINI.md.*