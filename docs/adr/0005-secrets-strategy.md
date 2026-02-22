# ADR 0005: Hybrid Secrets Management

## Status

Accepted

## Context

Need to manage secrets across environments:
- Infrastructure config (Lambda ARNs, bucket names)
- Runtime secrets (API keys, OAuth tokens)
- CI/CD variables

Requirements:
- Secrets should not be stored in Terraform state when possible
- Different access patterns for build-time vs runtime secrets
- Easy rotation for sensitive credentials

## Decision

Two-tier approach:

### Level 1: GitLab CI/CD Variables (Infrastructure Config)
Non-secret configuration values:
- AWS role ARNs
- State bucket names
- Region settings
- Environment names

### Level 2: AWS Secrets Manager (Runtime Secrets)
Sensitive values needed at runtime:
- MCP Lambda configurations
- OAuth credentials
- External API keys
- Database credentials

## Implementation

### GitLab CI/CD Variables

```
# Per environment group in GitLab Settings -> CI/CD -> Variables
CI_ENVIRONMENT_ROLE_ARN_DEV   = arn:aws:iam::111...:role/gitlab-terraform-deployer-dev
CI_ENVIRONMENT_ROLE_ARN_TEST  = arn:aws:iam::222...:role/gitlab-terraform-deployer-test
CI_ENVIRONMENT_ROLE_ARN_PROD  = arn:aws:iam::333...:role/gitlab-terraform-deployer-prod
TF_STATE_BUCKET_DEV           = terraform-state-dev-12345
TF_VAR_region                 = eu-central-1
TF_VAR_environment            = dev
```

### AWS Secrets Manager

```
Secret Path Structure:
agentcore/{environment}/{secret-type}

Examples:
- agentcore/dev/mcp-lambda-arns
- agentcore/dev/oauth-credentials
- agentcore/prod/api-keys
- agentcore/prod/gateway-config
```

### Terraform Reference

```hcl
data "aws_secretsmanager_secret_version" "mcp_config" {
  secret_id = "agentcore/${var.environment}/mcp-lambda-arns"
}

locals {
  mcp_targets = jsondecode(data.aws_secretsmanager_secret_version.mcp_config.secret_string)
}
```

## Rationale

### Why Two Tiers?

| Aspect | GitLab Variables | Secrets Manager |
|--------|-----------------|-----------------|
| Access time | Build time | Runtime |
| Rotation | Manual redeploy | Automatic |
| Cost | Free | $0.40/secret/month |
| Audit | GitLab logs | CloudTrail |
| Encryption | At rest | At rest + in transit |

### Why Not Just Secrets Manager?
- GitLab variables are simpler for non-secret config
- No additional API calls during `terraform plan`
- Free (included with GitLab)

### Why Not Just GitLab Variables?
- Cannot rotate without redeploy
- Limited audit trail
- No programmatic access from Lambda functions

## Consequences

### Positive
- Secrets not in Terraform state
- Automatic rotation available via Secrets Manager
- Fine-grained access control via IAM
- Audit logging via CloudTrail
- Runtime can fetch latest secrets without redeploy

### Negative
- Two systems to manage
- Additional AWS costs (~$0.40/secret/month)
- Runtime must have Secrets Manager IAM permissions
- Complexity of secret path conventions

## Secret Naming Convention

```
agentcore/{environment}/{secret-type}

Examples:
- agentcore/dev/mcp-lambda-arns      # JSON map of Lambda ARNs
- agentcore/dev/oauth-credentials    # OAuth client ID/secret
- agentcore/prod/api-keys            # External service API keys
- agentcore/prod/database            # Database connection strings
```

## Rotation Strategy

### OAuth Credentials
```bash
# Enable automatic rotation (Lambda-based)
aws secretsmanager rotate-secret \
  --secret-id agentcore/prod/oauth-credentials \
  --rotation-lambda-arn arn:aws:lambda:...:function:rotate-oauth \
  --rotation-rules AutomaticallyAfterDays=30
```

### API Keys
For external API keys, rotation depends on provider:
1. Generate new key in external service
2. Update Secrets Manager value
3. (Optional) Invalidate old key

## Alternatives Considered

1. **All in Terraform state** - Rejected (secrets visible in state file)
2. **HashiCorp Vault** - Rejected (additional infrastructure)
3. **AWS Parameter Store** - Considered (simpler but less features)
4. **Environment variables only** - Rejected (no rotation, limited audit)

## References

- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [GitLab CI/CD Variables](https://docs.gitlab.com/ee/ci/variables/)
- [Terraform Secrets Best Practices](https://developer.hashicorp.com/terraform/tutorials/configuration-language/sensitive-variables)
