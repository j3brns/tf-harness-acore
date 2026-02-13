# bootstrap_wif.ps1 - Setup AWS resources for GitLab WIF and Terraform State
#
# This script:
# 1. Creates an OIDC Provider for GitLab
# 2. Creates a scoped IAM Role for GitLab deployments
# 3. Creates an S3 bucket for Terraform state with locking & encryption

# --- Configuration (Override via $env:VarName) ---
$GitLabUrl = if ($env:GITLAB_URL) { $env:GITLAB_URL } else { "https://gitlab.com" }
$GitLabProjectPath = if ($env:GITLAB_PROJECT_PATH) { $env:GITLAB_PROJECT_PATH } else { "julian.burns50/ocds-agentcore" }
$AwsProfile = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "agentcore-terra" }
$AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "eu-west-2" }

# --- Derived Variables ---
$Uri = New-Object System.Uri($GitLabUrl)
$Domain = $Uri.Host
$AccountInfo = aws sts get-caller-identity --profile $AwsProfile --query "Account" --output text --no-cli-pager
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to get AWS Account ID. Check your profile."; exit 1 }
$AccountId = $AccountInfo.Trim()

$RoleName = "gitlab-terraform-deployer-dev"
$BucketName = "terraform-state-dev-$AccountId"

Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Starting Bootstrap for Account: $AccountId"
Write-Host "GitLab URL: $GitLabUrl"
Write-Host "Project Path: $GitLabProjectPath"
Write-Host "AWS Profile: $AwsProfile"
Write-Host "----------------------------------------------------------------"

# 1. Get OIDC Thumbprint (Native PowerShell method)
Write-Host "[1/4] Retrieving GitLab OIDC thumbprint..."
try {
    $TcpClient = New-Object System.Net.Sockets.TcpClient($Domain, 443)
    $SslStream = New-Object System.Net.Security.SslStream($TcpClient.GetStream())
    $SslStream.AuthenticateAsClient($Domain)
    $Thumbprint = $SslStream.RemoteCertificate.GetCertHashString("SHA1")
    $TcpClient.Close()
    Write-Host "Thumbprint: $Thumbprint"
} catch {
    Write-Error "Failed to retrieve SSL thumbprint from $Domain"
    exit 1
}

# 2. Create OIDC Provider
Write-Host "[2/4] Creating OIDC Provider in AWS..."
$ProviderArn = "arn:aws:iam::$AccountId:oidc-provider/$Domain"
$null = aws iam get-open-id-connect-provider --open-id-connect-provider-arn $ProviderArn --profile $AwsProfile 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "OIDC Provider already exists."
} else {
    aws iam create-open-id-connect-provider `
        --url $GitLabUrl `
        --client-id-list $GitLabUrl `
        --thumbprint-list $Thumbprint `
        --profile $AwsProfile --no-cli-pager
}

# 3. Create IAM Role and Scoped Policy
Write-Host "[3/4] Setting up IAM Role: $RoleName"

$TrustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$ProviderArn"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$($Domain):sub": "project_path:$GitLabProjectPath:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
"@

$PermissionsPolicy = @"
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
        "arn:aws:s3:::$BucketName",
        "arn:aws:s3:::$BucketName/*",
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
"@

$TrustPath = Join-Path $env:TEMP "trust-policy.json"
$PermsPath = Join-Path $env:TEMP "permissions-policy.json"

# Use .NET to write file WITHOUT BOM (Byte Order Mark)
[System.IO.File]::WriteAllText($TrustPath, $TrustPolicy)
[System.IO.File]::WriteAllText($PermsPath, $PermissionsPolicy)

# Fix paths for AWS CLI (convert backslashes to forward slashes)
$TrustPathUri = "file://" + $TrustPath.Replace("\", "/")
$PermsPathUri = "file://" + $PermsPath.Replace("\", "/")

$null = aws iam get-role --role-name $RoleName --profile $AwsProfile 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Role $RoleName already exists. Updating trust policy..."
    aws iam update-assume-role-policy --role-name $RoleName --policy-document "$TrustPathUri" --profile $AwsProfile --no-cli-pager
} else {
    aws iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document "$TrustPathUri" `
        --profile $AwsProfile --no-cli-pager
}

if ($LASTEXITCODE -eq 0) {
    aws iam put-role-policy `
        --role-name $RoleName `
        --policy-name "terraform-agentcore-policy" `
        --policy-document "$PermsPathUri" `
        --profile $AwsProfile --no-cli-pager
} else {
    Write-Error "Failed to create or update the role. JSON may still be malformed."
}

# 4. Create S3 State Bucket
Write-Host "[4/4] Provisioning S3 State Bucket: $BucketName"
$null = aws s3api head-bucket --bucket $BucketName --profile $AwsProfile 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Bucket already exists."
} else {
    aws s3 mb "s3://$BucketName" --region $AwsRegion --profile $AwsProfile --no-cli-pager
    
    aws s3api put-bucket-versioning `
        --bucket $BucketName `
        --versioning-configuration Status=Enabled `
        --profile $AwsProfile --no-cli-pager

    $EncryptionConfig = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    $EncPath = Join-Path $env:TEMP "encryption-config.json"
    [System.IO.File]::WriteAllText($EncPath, $EncryptionConfig)
    $EncPathUri = "file://" + $EncPath.Replace("\", "/")
    
    aws s3api put-bucket-encryption `
        --bucket $BucketName `
        --server-side-encryption-configuration "$EncPathUri" `
        --profile $AwsProfile --no-cli-pager

    aws s3api put-public-access-block `
        --bucket $BucketName `
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" `
        --profile $AwsProfile --no-cli-pager
}

Write-Host "----------------------------------------------------------------" -ForegroundColor Green
Write-Host "Bootstrap COMPLETE!"
# Using curly braces for variables to avoid colon expansion issues
Write-Host "Role ARN: arn:aws:iam::${AccountId}:role/${RoleName}"
Write-Host "S3 Bucket: ${BucketName}"
Write-Host "----------------------------------------------------------------"
Write-Host "Next Steps: Update GitLab CI/CD Variables with these values."
