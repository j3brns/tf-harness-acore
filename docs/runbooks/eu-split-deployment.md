# Runbook: EU Region Split Deployment

## Purpose

Deploy AgentCore in one EU region while using a different EU region for Bedrock models and/or the BFF/API Gateway.
Use this split **only if** the AgentCore control plane is not available in your preferred region (for example, London).
Always verify current regional availability before deciding to split.

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
2. Confirm Bedrock model and inference profile availability in `bedrock_region`.
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
