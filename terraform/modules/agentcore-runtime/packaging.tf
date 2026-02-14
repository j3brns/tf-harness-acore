# Two-stage build process for OCDS compliance
# Stage 1: Package dependencies from requirements/pyproject.toml

locals {
  source_path       = var.runtime_source_path
  dependencies_file = "${local.source_path}/pyproject.toml"
  build_dir         = "${path.module}/.build"
  deps_dir          = "${local.build_dir}/deps"

  # Hash files to trigger rebuilds
  dependencies_hash = fileexists(local.dependencies_file) ? filesha256(local.dependencies_file) : "no-dependencies"

  code_files = can(fileset(local.source_path, "**")) ? fileset(local.source_path, "**") : []

  code_files_hash = length(local.code_files) > 0 ? sha256(join("", [
    for f in sort(local.code_files) :
    filesha256("${local.source_path}/${f}")
  ])) : "no-code"

  # Combined hash for deployment package
  source_hash = sha256("${local.dependencies_hash}-${local.code_files_hash}")

  deployment_bucket = var.deployment_bucket_name != "" ? var.deployment_bucket_name : aws_s3_bucket.deployment[0].bucket
  archive_name      = "${var.agent_name}-${local.source_hash}.zip"
  deployment_key    = "deployments/${local.archive_name}"
}

# Stage 1: Package dependencies
resource "null_resource" "package_dependencies" {
  count = var.enable_packaging ? 1 : 0

  triggers = {
    dependencies_hash = local.dependencies_hash
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Stage 1: Packaging dependencies for ${var.agent_name}..."

      # Prepare local build directories
      mkdir -p "${local.build_dir}"
      rm -rf "${local.deps_dir}"
      mkdir -p "${local.deps_dir}"

      # Install dependencies
      if [ -f "${local.dependencies_file}" ]; then
        PLATFORM="manylinux2014_x86_64"
        if [ "${var.lambda_architecture}" == "arm64" ]; then
          PLATFORM="manylinux2014_aarch64"
        fi
        
        pip install --platform "$PLATFORM" \
          --target "${local.deps_dir}" \
          --implementation cp \
          --python ${var.python_version} \
          --only-binary=:all: \
          --upgrade \
          -r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
      fi

      # Generate metadata
      mkdir -p "${local.build_dir}/.terraform"
      echo "{\"status\": \"success\", \"timestamp\": \"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}" > "${local.build_dir}/.terraform/dependencies_metadata.json"

      echo "Dependencies packaged successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.runtime
  ]
}

# Stage 2: Package complete agent code
resource "null_resource" "package_code" {
  count = var.enable_packaging ? 1 : 0

  triggers = {
    code_hash         = local.code_files_hash
    dependencies_hash = local.dependencies_hash
    source_hash       = local.source_hash
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Stage 2: Packaging agent code for ${var.agent_name}..."

      # Create temporary directory for build artifacts
      BUILD_DIR=$(mktemp -d)
      trap "rm -rf $BUILD_DIR" EXIT

      # Validate source path exists
      if [ ! -d "${local.source_path}" ]; then
        echo "ERROR: Source path not found: ${local.source_path}"
        exit 1
      fi

      # Check source path is not empty
      if [ -z "$(ls -A '${local.source_path}')" ]; then
        echo "ERROR: Source path is empty: ${local.source_path}"
        exit 1
      fi

      # Copy source code
      mkdir -p "$BUILD_DIR/code"
      cp -r "${local.source_path}"/* "$BUILD_DIR/code/"

      # Copy dependencies (may be empty)
      mkdir -p "$BUILD_DIR/deps"
      if [ -d "${local.deps_dir}" ] && [ -n "$(ls -A "${local.deps_dir}")" ]; then
        cp -r "${local.deps_dir}"/* "$BUILD_DIR/deps/"
      fi

      # Create archive
      cd "$BUILD_DIR"
      ARCHIVE_NAME="${var.agent_name}-${self.triggers.source_hash}.zip"
      
      # Hardened exclusions (Rule 13 & Security)
      zip -r "$ARCHIVE_NAME" deps/ code/ \
        -x "*.git*" "__pycache__/*" "*.pyc" ".pytest_cache/*" \
        -x "*.env*" "*.tfvars*" ".terraform/*" ".venv/*" "venv/*" \
        -x "tests/*" "test/*" "*.log" ".DS_Store" "node_modules/*"

      # Verify archive was created
      if [ ! -f "$ARCHIVE_NAME" ]; then
        echo "ERROR: Failed to create deployment archive"
        exit 1
      fi

      # Upload to S3 with AWS-managed encryption (SSE-S3)
      aws s3 cp "$ARCHIVE_NAME" "s3://${local.deployment_bucket}/${local.deployment_key}" \
        --sse AES256

      # Generate metadata
      mkdir -p "$BUILD_DIR/.terraform"
      echo "{\"status\": \"success\", \"archive\": \"$ARCHIVE_NAME\", \"timestamp\": \"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}" > "$BUILD_DIR/.terraform/code_metadata.json"

      echo "Code packaged successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    null_resource.package_dependencies,
    aws_s3_bucket.deployment,
    aws_s3_bucket_server_side_encryption_configuration.deployment
  ]
}
