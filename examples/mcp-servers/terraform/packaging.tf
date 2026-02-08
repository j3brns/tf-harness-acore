# MCP Server Lambda Packaging
#
# Two-stage build following CLAUDE.md Rule 5:
# Stage 1: Dependencies (Lambda layer - cached)
# Stage 2: Code (deployment package - fresh each build)
#
# Structure:
#   examples/mcp-servers/
#   ├── s3-tools/
#   │   ├── handler.py
#   │   └── pyproject.toml
#   ├── titanic-data/
#   │   ├── handler.py
#   │   └── pyproject.toml
#   └── terraform/
#       └── .build/           # Generated artifacts (gitignored)
#           ├── s3-tools.zip
#           ├── titanic-data.zip
#           └── layers/
#               └── dependencies.zip

locals {
  # Source paths
  s3_tools_path     = "${path.module}/../s3-tools"
  titanic_data_path = "${path.module}/../titanic-data"
  build_dir         = "${path.module}/.build"

  # Hash source files for change detection
  s3_tools_files = var.deploy_s3_tools ? fileset(local.s3_tools_path, "**/*.py") : []
  s3_tools_hash = var.deploy_s3_tools ? sha256(join("", [
    for f in local.s3_tools_files : filesha256("${local.s3_tools_path}/${f}")
  ])) : "not-deployed"

  titanic_data_files = var.deploy_titanic_data ? fileset(local.titanic_data_path, "**/*.py") : []
  titanic_data_hash = var.deploy_titanic_data ? sha256(join("", [
    for f in local.titanic_data_files : filesha256("${local.titanic_data_path}/${f}")
  ])) : "not-deployed"

  # Dependencies detection
  s3_tools_deps_file     = "${local.s3_tools_path}/pyproject.toml"
  titanic_data_deps_file = "${local.titanic_data_path}/pyproject.toml"

  s3_tools_has_deps     = var.deploy_s3_tools && fileexists(local.s3_tools_deps_file)
  titanic_data_has_deps = var.deploy_titanic_data && fileexists(local.titanic_data_deps_file)

  # boto3 is included in Lambda runtime - check if we need extra deps
  s3_tools_needs_layer = local.s3_tools_has_deps && can(regex("dependencies\\s*=\\s*\\[\\s*[^\\]]+", file(local.s3_tools_deps_file)))
}

# -----------------------------------------------------------------------------
# Stage 1: Dependencies Layer (Optional - only if non-runtime deps needed)
# -----------------------------------------------------------------------------
# Note: boto3 is included in Lambda runtime, so s3-tools doesn't need a layer
# This is prepared for MCP servers that need pandas, numpy, etc.

resource "null_resource" "build_dependencies_layer" {
  count = var.enable_dependencies_layer ? 1 : 0

  triggers = {
    s3_tools_deps     = local.s3_tools_has_deps ? filesha256(local.s3_tools_deps_file) : "none"
    titanic_data_deps = local.titanic_data_has_deps ? filesha256(local.titanic_data_deps_file) : "none"
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      echo "Building dependencies layer..."

      # Create build directory
      mkdir -p "${local.build_dir}/layers/python/lib/python3.12/site-packages"

      # Install s3-tools dependencies (skip boto3 - already in Lambda)
      if [ -f "${local.s3_tools_deps_file}" ]; then
        # Extract non-boto3 dependencies
        grep -E "^[[:space:]]*\"[a-zA-Z]" "${local.s3_tools_deps_file}" | \
          grep -v "boto3" | \
          sed 's/[",]//g' | \
          xargs -r pip install \
            --platform manylinux2014_x86_64 \
            --target "${local.build_dir}/layers/python/lib/python3.12/site-packages" \
            --implementation cp \
            --python-version 3.12 \
            --only-binary=:all: \
            --upgrade || true
      fi

      # Create layer zip
      cd "${local.build_dir}/layers"
      if [ -d "python" ] && [ "$(ls -A python/lib/python3.12/site-packages 2>/dev/null)" ]; then
        zip -r dependencies.zip python/
        echo "Layer built: dependencies.zip"
      else
        echo "No additional dependencies to layer"
        echo '{"empty": true}' > dependencies.json
      fi
    EOT
    interpreter = ["bash", "-c"]
  }
}

# -----------------------------------------------------------------------------
# Stage 2: Code Packages
# -----------------------------------------------------------------------------

# S3 Tools - Package entire directory
data "archive_file" "s3_tools" {
  count       = var.deploy_s3_tools ? 1 : 0
  type        = "zip"
  source_dir  = local.s3_tools_path
  output_path = "${local.build_dir}/s3-tools.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    ".pytest_cache",
    "tests",
    ".git",
    "*.egg-info"
  ]
}

# Titanic Data - Package entire directory
data "archive_file" "titanic_data" {
  count       = var.deploy_titanic_data ? 1 : 0
  type        = "zip"
  source_dir  = local.titanic_data_path
  output_path = "${local.build_dir}/titanic-data.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    ".pytest_cache",
    "tests",
    ".git",
    "*.egg-info"
  ]
}

# -----------------------------------------------------------------------------
# Lambda Layer (Optional)
# -----------------------------------------------------------------------------

resource "aws_lambda_layer_version" "mcp_dependencies" {
  count = var.enable_dependencies_layer && fileexists("${local.build_dir}/layers/dependencies.zip") ? 1 : 0

  filename            = "${local.build_dir}/layers/dependencies.zip"
  layer_name          = "${var.name_prefix}-mcp-dependencies-${var.environment}"
  compatible_runtimes = ["python3.12"]
  description         = "Shared dependencies for MCP server Lambdas"

  depends_on = [null_resource.build_dependencies_layer]
}

# -----------------------------------------------------------------------------
# Outputs for debugging
# -----------------------------------------------------------------------------

output "packaging_info" {
  description = "Packaging details for debugging"
  value = {
    s3_tools = var.deploy_s3_tools ? {
      source_path   = local.s3_tools_path
      source_hash   = local.s3_tools_hash
      package_path  = "${local.build_dir}/s3-tools.zip"
      has_deps_file = local.s3_tools_has_deps
    } : null
    titanic_data = var.deploy_titanic_data ? {
      source_path   = local.titanic_data_path
      source_hash   = local.titanic_data_hash
      package_path  = "${local.build_dir}/titanic-data.zip"
      has_deps_file = local.titanic_data_has_deps
    } : null
    layer_enabled = var.enable_dependencies_layer
  }
}
