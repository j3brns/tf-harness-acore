# Web Identity Federation (WIF) Setup Guide

This guide covers setting up AWS Web Identity Federation for GitLab CI/CD pipelines to enable secure, credential-free authentication.

## Overview

Web Identity Federation allows GitLab CI/CD to authenticate to AWS without storing static credentials. Instead, GitLab generates a short-lived OIDC token that AWS trusts.

**Key Benefits**:
- No long-lived credentials to rotate or leak
- Automatic token expiration (job duration)
- Fine-grained access control per branch/tag
- Full CloudTrail audit trail

## Architecture

```
GitLab Runner          AWS                    AWS Resources
+------------+        +------------------+    +---------------+
| CI/CD Job  |------->| IAM OIDC Provider|    | S3 State      |
| $CI_JOB_JWT|        +------------------+    | Bedrock       |
+------------+               |                | Lambda        |
      |                      v                | CloudWatch    |
      |               +------------------+    +---------------+
      +-------------->| IAM Role         |          ^
                      | Trust Policy     |----------|
                      | + Scoped Policy  |
                      +------------------+
```

**Flow**:
1. GitLab CI job starts and receives `$CI_JOB_JWT_V2` token
2. Job exports token to file for AWS SDK
3. AWS STS validates token against OIDC provider
4. STS returns temporary credentials (1 hour validity)
5. Terraform uses credentials for AWS operations

## Setup Steps

### Step 1: Create OIDC Provider in AWS

Run this in each AWS account (dev, test, prod):

```bash
# Get GitLab's OIDC thumbprint
# Replace gitlab.yourcompany.com with your GitLab URL
GITLAB_URL="https://gitlab.yourcompany.com"

# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url "${GITLAB_URL}" \
  --client-id-list "${GITLAB_URL}" \
  --thumbprint-list "$(openssl s_client -connect gitlab.yourcompany.com:443 -servername gitlab.yourcompany.com 2>/dev/null | openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d ':')"
```

### Step 2: Create IAM Role

Create a role in each AWS account that GitLab can assume.

#### Trust Policy

Save as `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.yourcompany.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.yourcompany.com:sub": "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

**Important**: Update:
- `ACCOUNT_ID` with your AWS account ID
- `gitlab.yourcompany.com` with your GitLab URL
- `mygroup/terraform-agentcore` with your project path

#### Permissions Policy (Scoped - SEC-008)

**IMPORTANT**: This policy replaces `PowerUserAccess` with scoped permissions following least-privilege principles.

Save as `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAgentCore",
      "Effect": "Allow",
      "Action": [
        "bedrock:*",
        "bedrock-agent:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["eu-central-1"]
        }
      }
    },
    {
      "Sid": "S3StateAndArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-state-*",
        "arn:aws:s3:::terraform-state-*/*",
        "arn:aws:s3:::agentcore-*",
        "arn:aws:s3:::agentcore-*/*"
      ]
    },
    {
      "Sid": "S3CreateBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketVersioning",
        "s3:PutBucketEncryption",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketPolicy"
      ],
      "Resource": "arn:aws:s3:::agentcore-*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagResource",
        "logs:ListTagsForResource"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/bedrock/agentcore/*"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["eu-central-1"]
        }
      }
    },
    {
      "Sid": "XRay",
      "Effect": "Allow",
      "Action": [
        "xray:CreateSamplingRule",
        "xray:DeleteSamplingRule",
        "xray:GetSamplingRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:ListVersionsByFunction",
        "lambda:PublishVersion",
        "lambda:CreateAlias",
        "lambda:UpdateAlias",
        "lambda:DeleteAlias",
        "lambda:GetAlias",
        "lambda:TagResource",
        "lambda:ListTags",
        "lambda:AddPermission",
        "lambda:RemovePermission"
      ],
      "Resource": [
        "arn:aws:lambda:*:*:function:*-mcp",
        "arn:aws:lambda:*:*:function:*-mcp:*"
      ]
    },
    {
      "Sid": "LambdaLayers",
      "Effect": "Allow",
      "Action": [
        "lambda:PublishLayerVersion",
        "lambda:GetLayerVersion",
        "lambda:DeleteLayerVersion"
      ],
      "Resource": "arn:aws:lambda:*:*:layer:*-mcp-*"
    },
    {
      "Sid": "IAMRolesForAgentCore",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/agentcore-*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/agentcore-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "lambda.amazonaws.com",
            "bedrock.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:TagResource",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:agentcore/*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

**Why scoped?** The previous `PowerUserAccess` allowed nearly all AWS actions. This policy:
- Limits Bedrock to eu-central-1 region
- Restricts S3 to named bucket patterns only
- Scopes Lambda to `*-mcp` function naming convention
- Limits IAM to `agentcore-*` role names only
- Adds `iam:PassRole` conditions for service principals

#### Create Role

```bash
# Create role
aws iam create-role \
  --role-name gitlab-terraform-deployer-dev \
  --assume-role-policy-document file://trust-policy.json

# Create and attach policy
aws iam put-role-policy \
  --role-name gitlab-terraform-deployer-dev \
  --policy-name terraform-agentcore-policy \
  --policy-document file://permissions-policy.json
```

### Step 3: Configure GitLab CI/CD Variables

In GitLab, go to **Settings > CI/CD > Variables** and add:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `CI_ENVIRONMENT_ROLE_ARN_DEV` | `arn:aws:iam::111111111111:role/gitlab-terraform-deployer-dev` | Yes | No |
| `CI_ENVIRONMENT_ROLE_ARN_TEST` | `arn:aws:iam::222222222222:role/gitlab-terraform-deployer-test` | Yes | No |
| `CI_ENVIRONMENT_ROLE_ARN_PROD` | `arn:aws:iam::333333333333:role/gitlab-terraform-deployer-prod` | Yes | No |
| `TF_STATE_BUCKET_DEV` | `terraform-state-dev-12345` | No | No |
| `TF_STATE_BUCKET_TEST` | `terraform-state-test-12345` | No | No |
| `TF_STATE_BUCKET_PROD` | `terraform-state-prod-12345` | No | No |

### Step 4: Create State Infrastructure

Before first pipeline run, create S3 buckets for state storage:

```bash
# For each environment (dev, test, prod):
ENV="dev"
BUCKET="terraform-state-${ENV}-$(aws sts get-caller-identity --query Account --output text)"

# Create S3 bucket
aws s3 mb "s3://${BUCKET}" --region eu-central-1

# Enable versioning (for state history and recovery)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**Note**: No DynamoDB table is needed. Terraform 1.10.0+ uses native S3 locking via `use_lockfile = true`.

## Verification

Test the WIF setup:

```bash
# In GitLab CI job (or locally with JWT):
export AWS_ROLE_ARN="arn:aws:iam::111111111111:role/gitlab-terraform-deployer-dev"
export AWS_WEB_IDENTITY_TOKEN_FILE="/tmp/token"
echo "$CI_JOB_JWT_V2" > /tmp/token

# Verify
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AROA...:gitlab-mygroup-terraform-12345",
    "Account": "111111111111",
    "Arn": "arn:aws:sts::111111111111:assumed-role/gitlab-terraform-deployer-dev/gitlab-mygroup-terraform-12345"
}
```

## Troubleshooting

### Error: "Token is expired"

The OIDC token has a short lifetime. Ensure:
- Job completes within token lifetime (~1 hour)
- Token is refreshed for long-running jobs

### Error: "Invalid principal in policy"

Check that:
- OIDC provider URL matches exactly
- Project path in condition matches GitLab project

### Error: "Access Denied"

Verify:
- Role ARN is correct
- Policy allows required actions
- Resource ARNs in policy match actual resources

### Error: "OIDC thumbprint mismatch"

If GitLab updates its certificate:

```bash
# Get new thumbprint
openssl s_client -servername gitlab.yourcompany.com \
  -connect gitlab.yourcompany.com:443 < /dev/null 2>/dev/null | \
  openssl x509 -fingerprint -sha1 -noout

# Update OIDC provider
PROVIDER_ARN="arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.yourcompany.com"
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn $PROVIDER_ARN \
  --thumbprint-list NEW_THUMBPRINT
```

### Error: "Could not load credentials"

Check that:
1. `AWS_WEB_IDENTITY_TOKEN_FILE` points to valid file
2. File contains the JWT token (not empty)
3. `AWS_ROLE_ARN` is set correctly

Debug with:
```bash
cat $AWS_WEB_IDENTITY_TOKEN_FILE | cut -c1-50
echo "Role: $AWS_ROLE_ARN"
```

## Trust Policy Conditions

### Branch-Specific Access

Restrict to main branch only:

```json
{
  "Condition": {
    "StringEquals": {
      "gitlab.yourcompany.com:sub": "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:main"
    }
  }
}
```

### Tag-Only Access (Recommended for Production)

```json
{
  "Condition": {
    "StringLike": {
      "gitlab.yourcompany.com:sub": "project_path:mygroup/terraform-agentcore:ref_type:tag:ref:v*"
    }
  }
}
```

### Multiple Branches (for Test)

```json
{
  "Condition": {
    "StringLike": {
      "gitlab.yourcompany.com:sub": [
        "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:main",
        "project_path:mygroup/terraform-agentcore:ref_type:branch:ref:release/*"
      ]
    }
  }
}
```

## Environment Mapping

| GitLab Branch/Tag | AWS Account | IAM Role | State Bucket |
|-------------------|-------------|----------|--------------|
| `main` | Dev | `gitlab-terraform-deployer-dev` | `terraform-state-dev-*` |
| `release/*` | Test | `gitlab-terraform-deployer-test` | `terraform-state-test-*` |
| `v*` (tags) | Prod | `gitlab-terraform-deployer-prod` | `terraform-state-prod-*` |

## Security Best Practices

1. **Use scoped policies** - Never use `PowerUserAccess` or `AdministratorAccess`
2. **Restrict by branch** - Prod role should only trust tags (`v*`)
3. **Separate accounts** - Use different AWS accounts for dev/test/prod
4. **Audit access** - Enable CloudTrail for WIF and IAM events
5. **Rotate thumbprints** - Check after GitLab certificate renewals
6. **Limit IAM permissions** - Only allow `iam:PassRole` to specific services
7. **Protected variables** - Mark role ARNs as protected in GitLab

## Quick Reference

### GitLab CI/CD Integration

The `.gitlab-ci.yml` uses WIF like this:

```yaml
.terraform_setup:
  before_script:
    - export AWS_ROLE_ARN=${CI_ENVIRONMENT_ROLE_ARN_DEV}
    - export AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/token
    - echo "$CI_JOB_JWT_V2" > /tmp/token
    - aws sts get-caller-identity
```

### Local Testing (Optional)

To test WIF locally with a GitLab personal access token:

```bash
# This requires GitLab 15.7+ with ID tokens enabled
# Usually easier to test via actual CI job
```

## References

- [GitLab CI/CD OIDC](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
- [AWS IAM OIDC Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [ADR 0003: GitLab CI with WIF](adr/0003-gitlab-ci-pipeline.md)
