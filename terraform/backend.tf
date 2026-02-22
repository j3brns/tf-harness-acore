# ADR 0013: Segmented S3 Backend (Partial Configuration)
# Use 'terraform init -backend-config=path/to/backend.tfvars' or command line arguments
# to provide the 'bucket', 'key', and 'region' for the backend.

terraform {
  backend "s3" {
    # The 'bucket' and 'key' MUST be provided during init.
    # Pattern for 'key': state/${app_id}/${agent_name}/terraform.tfstate

    use_lockfile = true
    encrypt      = true
  }
}
