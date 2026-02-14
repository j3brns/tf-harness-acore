# ADR 0003: GitLab CI/CD with Web Identity Federation

## Status

Accepted

## Context

Need CI/CD pipeline for automated testing and deployment.
- GitLab CI is the primary deployment pipeline
- Repository is mirrored on GitHub (GitHub Actions used for minimal validation)
- Three AWS accounts (dev, test, prod) for environments
- Need secure authentication without storing credentials
- Want maximum local testing before AWS deployment

## Decision

Use GitLab CI with:
- 12 stages (validate, lint, test, plan-dev, deploy-dev, smoke-test-dev, plan-test, deploy-test, smoke-test-test, plan-prod, deploy-prod, smoke-test-prod)
- AWS Web Identity Federation (WIF) for authentication
- Branch/tag promotion:
  - `main` -> dev plan + auto deploy + smoke test
  - `release/*` -> test plan + manual deploy + smoke test
  - tags -> prod plan + manual deploy + smoke test
- Maximum local testing (no AWS for validate/lint/test stages)
- Scheduled drift detection (non-blocking) runs in the test stage

## Pipeline Structure

```yaml
stages:
  - validate        # Terraform fmt, validate (NO AWS)
  - lint            # TFLint, Checkov (NO AWS)
  - test            # Example validation, Cedar policies (NO AWS)
  - plan-dev        # Plan dev deployment (no apply)
  - deploy-dev      # Auto-deploy to dev (AWS dev account)
  - smoke-test-dev  # Verify dev deployment
  - plan-test       # Plan test deployment for review
  - deploy-test     # Manual deploy to test (AWS test account)
  - smoke-test-test # Verify test deployment
  - plan-prod       # Plan prod deployment for review
  - deploy-prod     # Manual deploy to prod (AWS prod account)
  - smoke-test-prod # Verify prod deployment
```

## WIF Authentication Flow

```
GitLab CI Job
    |
    v
OIDC Token (JWT)
    |
    v
AWS STS AssumeRoleWithWebIdentity
    |
    v
Temporary Credentials (15 min - 1 hour)
    |
    v
Terraform commands with AWS access
```

## Rationale

- GitLab CI is the deployment control plane
- WIF more secure than static IAM credentials (no secrets to rotate)
- Branch/tag strategy provides clear promotion path with explicit plan gates
- Local testing reduces AWS costs
- Stages 1-3 run without AWS account

## Consequences

### Positive
- No AWS credentials stored in GitLab
- Clear environment promotion workflow
- Zero-cost testing (local only) for first 3 stages
- Audit trail via git history
- Temporary credentials auto-expire

### Negative
- Initial WIF setup complexity
- Requires GitLab admin access for OIDC configuration
- Need separate OIDC provider per AWS account
- Debugging WIF issues can be challenging

## Alternatives Considered

1. **Static IAM credentials** - Rejected (security risk, rotation overhead)
2. **GitHub Actions** - Rejected (repo on GitHub temporarily, but target is GitLab)
3. **Jenkins** - Rejected (GitLab already available with built-in CI)
4. **AWS CodePipeline** - Rejected (prefer GitOps pattern with IaC in git)

## Implementation Notes

While the repository is hosted on GitHub, a minimal GitHub Actions workflow runs validation only.
GitLab CI remains the source of truth for environment deployments with WIF.

### GitLab CI Variables Required

```
CI_ENVIRONMENT_ROLE_ARN_DEV:  arn:aws:iam::111...:role/gitlab-terraform-deployer-dev
CI_ENVIRONMENT_ROLE_ARN_TEST: arn:aws:iam::222...:role/gitlab-terraform-deployer-test
CI_ENVIRONMENT_ROLE_ARN_PROD: arn:aws:iam::333...:role/gitlab-terraform-deployer-prod
TF_STATE_BUCKET_DEV:  terraform-state-dev-12345
TF_STATE_BUCKET_TEST: terraform-state-test-12345
TF_STATE_BUCKET_PROD: terraform-state-prod-12345
```

### IAM Trust Policy (per AWS account)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/gitlab.yourcompany.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "gitlab.yourcompany.com:sub": "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:main"
      }
    }
  }]
}
```

## References

- [GitLab CI/CD OpenID Connect](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
