#!/bin/bash
# bootstrap_wif.sh - Setup AWS resources for GitLab WIF and Terraform State
#
# This script:
# 1. Creates an OIDC Provider for GitLab
# 2. Creates a scoped IAM Role for GitLab deployments
# 3. Creates an S3 bucket for Terraform state with locking & encryption

set -euo pipefail

# --- Configuration (Override via env vars) ---
GITLAB_URL="${GITLAB_URL:-https://gitlab.yourcompany.com}"
GITLAB_PROJECT_PATH="${GITLAB_PROJECT_PATH:-mygroup/terraform-agentcore}"
AWS_PROFILE="${AWS_PROFILE:-agentcore-terra}"
AWS_REGION="${AWS_REGION:-eu-west-2}"

# --- Derived Variables ---
DOMAIN=$(echo "$GITLAB_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
ROLE_NAME="gitlab-terraform-deployer-dev"
BUCKET_NAME="terraform-state-dev-${ACCOUNT_ID}"

echo "----------------------------------------------------------------"
echo "Starting Bootstrap for Account: ${ACCOUNT_ID}"
echo "GitLab URL: ${GITLAB_URL}"
echo "Project Path: ${GITLAB_PROJECT_PATH}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "----------------------------------------------------------------"

# 1. Get OIDC Thumbprint
echo "[1/4] Retrieving GitLab OIDC thumbprint..."
THUMBPRINT=$(openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null 
  | openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d ':')
echo "Thumbprint: ${THUMBPRINT}"

# 2. Create OIDC Provider
echo "[2/4] Creating OIDC Provider in AWS..."
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${DOMAIN}" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "OIDC Provider already exists."
else
  aws iam create-open-id-connect-provider 
    --url "${GITLAB_URL}" 
    --client-id-list "${GITLAB_URL}" 
    --thumbprint-list "${THUMBPRINT}" 
    --profile "$AWS_PROFILE"
fi

# 3. Create IAM Role and Scoped Policy
echo "[3/4] Setting up IAM Role: ${ROLE_NAME}"

# Create Trust Policy
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${DOMAIN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${DOMAIN}:sub": "project_path:${GITLAB_PROJECT_PATH}:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
EOF

# Create Permissions Policy (Scoped)
cat > /tmp/permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
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
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*",
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
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
EOF

# Create Role
if aws iam get-role --role-name "${ROLE_NAME}" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "Role ${ROLE_NAME} already exists. Updating trust policy..."
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document file:///tmp/trust-policy.json --profile "$AWS_PROFILE"
else
  aws iam create-role 
    --role-name "${ROLE_NAME}" 
    --assume-role-policy-document file:///tmp/trust-policy.json 
    --profile "$AWS_PROFILE"
fi

# Attach Scoped Policy
aws iam put-role-policy 
  --role-name "${ROLE_NAME}" 
  --policy-name "terraform-agentcore-policy" 
  --policy-document file:///tmp/permissions-policy.json 
  --profile "$AWS_PROFILE"

# 4. Create S3 State Bucket
echo "[4/4] Provisioning S3 State Bucket: ${BUCKET_NAME}"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "Bucket already exists."
else
  aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" --profile "$AWS_PROFILE"
  
  aws s3api put-bucket-versioning 
    --bucket "${BUCKET_NAME}" 
    --versioning-configuration Status=Enabled 
    --profile "$AWS_PROFILE"

  aws s3api put-bucket-encryption 
    --bucket "${BUCKET_NAME}" 
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' 
    --profile "$AWS_PROFILE"

  aws s3api put-public-access-block 
    --bucket "${BUCKET_NAME}" 
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" 
    --profile "$AWS_PROFILE"
fi

echo "----------------------------------------------------------------"
echo "Bootstrap COMPLETE!"
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "S3 Bucket: ${BUCKET_NAME}"
echo "----------------------------------------------------------------"
echo "Next Steps: Update GitLab CI/CD Variables with these values."
