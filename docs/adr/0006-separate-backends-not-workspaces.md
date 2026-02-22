# ADR 0006: Separate Backends Instead of Workspaces

## Status

Accepted

## Context

Need to manage Terraform state across multiple environments (dev, test, prod).

Two common patterns:
1. **Workspaces**: Single backend, multiple workspaces (`terraform workspace select dev`)
2. **Separate backends**: Different S3 buckets per environment

## Decision

Use separate backends (one per environment) instead of Terraform workspaces.

```hcl
# backend-dev.tfvars
bucket = "terraform-state-dev-12345"
key    = "state/my-app/agent-a1b2/terraform.tfstate"
region = "eu-central-1"
encrypt = true

# backend-prod.tfvars
bucket = "terraform-state-prod-67890"
key    = "state/my-app/agent-c3d4/terraform.tfstate"
region = "eu-central-1"
encrypt = true
```

## Rationale

### Blast Radius Containment

| Scenario | Workspaces | Separate Backends |
|----------|------------|-------------------|
| Wrong workspace selected | Prod resources affected | Different credentials needed |
| State corruption | All environments at risk | Only one environment affected |
| Credential leak | All environments exposed | Only one environment exposed |

### Access Control

With separate backends in separate AWS accounts:
- Dev team has access to dev state only
- Prod state requires elevated permissions
- Clear audit trail per environment

### Operational Safety

```bash
# With workspaces - easy to make mistakes
terraform workspace select prod  # Did I switch correctly?
terraform destroy                # Oops, wrong workspace!

# With separate backends - explicit configuration
terraform init -backend-config=backend-prod.tf  # Explicit
terraform destroy  # Clear which environment
```

## Consequences

### Positive
- Blast radius limited to single environment
- Clear access control boundaries
- Harder to accidentally affect wrong environment
- State files in environment-specific AWS accounts
- Simpler debugging (one environment per state file)

### Negative
- More backend configuration files
- Need to reinitialize when switching environments
- Cannot easily compare state across environments
- More S3 buckets to manage (one per environment)

## Implementation

### Directory Structure
```
terraform/
+-- backend-dev.tfvars.example
+-- backend-test.tfvars.example
+-- backend-prod.tfvars.example
+-- backend.tf
+-- main.tf
+-- variables.tf
```

### Switching Environments
```bash
# Switch to dev
cd terraform
rm -rf .terraform
terraform init -backend-config=backend-dev.tf

# Switch to prod (requires re-init)
rm -rf .terraform
terraform init -backend-config=backend-prod.tf
```

### CI/CD Integration
```yaml
# GitLab CI generates backend config per environment
deploy:dev:
  script:
    - |
      cat > backend.tf <<EOF
      terraform {
        backend "s3" {
          bucket = "${TF_STATE_BUCKET_DEV}"
          key    = "agentcore/terraform.tfstate"
        }
      }
      EOF
    - terraform init
    - terraform apply
```

## Alternatives Considered

1. **Terraform workspaces** - Rejected (blast radius too large)
2. **Single bucket with prefixes** - Rejected (still single point of failure)
3. **Terraform Cloud workspaces** - Rejected (external SaaS dependency)

## Workspace Use Cases (Still Valid)

Workspaces are still useful for:
- Temporary development environments (`feature-xyz`)
- Testing infrastructure variations
- Non-production experimentation

But NOT for:
- Production vs non-production isolation
- Multi-account deployments
- Compliance-separated environments

## References

- [Terraform Workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces)
- [Backend Configuration](https://developer.hashicorp.com/terraform/language/settings/backends/configuration)
- [Multi-Environment Best Practices](https://developer.hashicorp.com/terraform/tutorials/terraform/modules/organize-configuration)
