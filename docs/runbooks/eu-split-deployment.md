# Runbook: EU Region Split Deployment

## Purpose

Deploy AgentCore in one EU region while using a different EU region for Bedrock models and/or the BFF/API Gateway.
Use this split **only if** the AgentCore control plane is not available in your preferred region (for example, London).
Always verify current regional availability before deciding to split.

## Region Source-of-Truth Policy (checked `2026-02-25`)

Use different AWS sources for different decisions:

1. **AgentCore deployability in `agentcore_region` (hard fail in repo)**
   Source of truth: AWS General Reference AgentCore endpoints (control + data plane) for this repo's deployability path.
2. **AgentCore feature coverage in `agentcore_region` (hard fail in Terraform)**
   Source of truth: AgentCore feature-region matrix (Runtime/Gateway/Policy/Evaluations/etc.).
3. **Bedrock model/inference behavior in `bedrock_region` (operator check, repo warns only)**
   Source of truth: Bedrock model support + inference profile support + cross-Region inference (CRIS) docs, including IAM/SCP destination-region requirements.

This repo's `make validate-region` enforces (1), Terraform preconditions enforce common cases for (2), and `make validate-region` emits guidance warnings for split `bedrock_region` configs under (3) but does not validate model-specific Bedrock support.

## Recommended EU Mappings

Common patterns:

1. **AgentCore Dublin, Bedrock London, BFF London**
```hcl
region           = "eu-west-1"
agentcore_region = "eu-west-1"
bedrock_region   = "eu-west-2"
bff_region       = "eu-west-2"
```

2. **AgentCore Frankfurt, Bedrock London, BFF London**
```hcl
region           = "eu-central-1"
agentcore_region = "eu-central-1"
bedrock_region   = "eu-west-2"
bff_region       = "eu-west-2"
```

3. **All resources in Dublin**
```hcl
region           = "eu-west-1"
agentcore_region = ""
bedrock_region   = ""
bff_region       = ""
```

## Preconditions

1. Confirm AgentCore availability in the chosen `agentcore_region` (check AWS regional availability).
   Recommended repo check:
   ```bash
   make validate-region TFVARS=../examples/your-agent/terraform.tfvars
   ```
2. Confirm Bedrock model and inference profile availability in `bedrock_region`.
   If using cross-Region inference (CRIS), confirm IAM/SCP permissions allow all destination Regions for the selected profile.
3. Ensure MCP Lambda ARNs in `mcp_targets` exist in `agentcore_region`.
4. If BFF is split, update OAuth redirect URIs for the BFF region domain.

## Deploy

```bash
cd terraform
terraform init
terraform plan -var-file=../examples/your-agent/terraform.tfvars
terraform apply -var-file=../examples/your-agent/terraform.tfvars
```

## Validate

AgentCore resources in `agentcore_region`:
```bash
aws bedrock-agentcore-control list-gateways --region eu-west-1
aws bedrock-agentcore-control list-agents --region eu-west-1
```

Bedrock models in `bedrock_region`:
```bash
aws bedrock list-foundation-models --region eu-west-2
```

BFF/API Gateway in `bff_region`:
```bash
aws apigateway get-rest-apis --region eu-west-2
```

## Common Issues

1. `ResourceNotFound` from proxy Lambda: check `AGENTCORE_REGION` environment variable and `agentcore_region` value.
2. `AccessDenied` from Bedrock: ensure `bedrock_region` matches model availability and IAM policy scoping matches the region.
3. Missing logs: check CloudWatch in the correct region for BFF (`bff_region`) and AgentCore (`agentcore_region`).

## Rollback

Set `agentcore_region`, `bedrock_region`, and `bff_region` to empty values and re-apply to return to single-region deployment.

## Sources (checked `2026-02-25`)

- AWS General Reference (AgentCore endpoints): https://docs.aws.amazon.com/general/latest/gr/bedrock_agentcore.html
- AgentCore feature-region matrix: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html
- Amazon Bedrock cross-Region inference (CRIS): https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference.html
- Amazon Bedrock inference profile region support: https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html
