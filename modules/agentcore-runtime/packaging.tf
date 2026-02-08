# Two-stage build process for OCDS compliance
# Stage 1: Package dependencies from requirements/pyproject.toml

locals {
  source_path       = var.runtime_source_path
  dependencies_file = "${local.source_path}/pyproject.toml"

  # Hash files to trigger rebuilds
  dependencies_hash = fileexists(local.dependencies_file) ? filesha256(local.dependencies_file) : "no-dependencies"

  code_files = fileexists(local.source_path) ? setunion(
    [for f in fileset(local.source_path, "**/*.py") : "${local.source_path}/${f}"],
    [for f in fileset(local.source_path, "**/*.txt") : "${local.source_path}/${f}"],
    [for f in fileset(local.source_path, "**/*.json") : "${local.source_path}/${f}"]
  ) : []

  code_files_hash = length(local.code_files) > 0 ? sha256(join(",", sort(local.code_files))) : "no-code"

  # Combined hash for deployment package
  source_hash = sha256("${local.dependencies_hash}-${local.code_files_hash}")

  deployment_bucket = var.deployment_bucket_name != "" ? var.deployment_bucket_name : aws_s3_bucket.deployment[0].bucket
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

      # Create temporary directory for build artifacts
      BUILD_DIR=$(mktemp -d)
      trap "rm -rf $BUILD_DIR" EXIT

      # Create dependencies layer
      DEP_LAYER="$BUILD_DIR/dependencies"
      mkdir -p "$DEP_LAYER/python/lib/python${var.python_version}/site-packages"

      # Install dependencies
      if [ -f "${local.dependencies_file}" ]; then
        pip install --platform manylinux2014_x86_64 \
          --target "$DEP_LAYER/python/lib/python${var.python_version}/site-packages" \
          --implementation cp \
          --python ${var.python_version} \
          --only-binary=:all: \
          --upgrade \
          -r <(grep -E "^[a-zA-Z]" "${local.dependencies_file}")
      fi

      # Generate metadata
      mkdir -p "$BUILD_DIR/.terraform"
      echo "{\"status\": \"success\", \"timestamp\": \"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}" > "$BUILD_DIR/.terraform/dependencies_metadata.json"

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

      # Create archive
      cd "$BUILD_DIR"
      ARCHIVE_NAME="${var.agent_name}-$(date +%s).zip"
      zip -r "$ARCHIVE_NAME" code/ -x "*.git*" "__pycache__/*" "*.pyc" ".pytest_cache/*"

      # Verify archive was created
      if [ ! -f "$ARCHIVE_NAME" ]; then
        echo "ERROR: Failed to create deployment archive"
        exit 1
      fi

      # Upload to S3 with AWS-managed encryption (SSE-S3)
      aws s3 cp "$ARCHIVE_NAME" "s3://${local.deployment_bucket}/deployments/" \
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
