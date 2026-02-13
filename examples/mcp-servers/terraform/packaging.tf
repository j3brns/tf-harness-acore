# MCP Server Lambda Packaging
#
# Two-stage build required by AGENTS.md:
# 1) deps/ installed via pip
# 2) code/ copied from source
# 3) deployment zip contains deps/ + code/

locals {
  # Source paths
  s3_tools_path     = "${path.module}/../s3-tools"
  titanic_data_path = "${path.module}/../titanic-data"
  awscli_tools_path = "${path.module}/../awscli-tools"
  build_dir         = "${path.module}/.build"

  # Dependency files (requirements.txt)
  s3_tools_requirements     = "${local.s3_tools_path}/requirements.txt"
  titanic_data_requirements = "${local.titanic_data_path}/requirements.txt"
  awscli_tools_requirements = "${local.awscli_tools_path}/requirements.txt"

  # Source hashes for change detection
  s3_tools_files = var.deploy_s3_tools ? fileset(local.s3_tools_path, "**") : []
  s3_tools_source_hash = var.deploy_s3_tools ? sha256(join("", [
    for f in local.s3_tools_files : filesha256("${local.s3_tools_path}/${f}")
  ])) : "not-deployed"
  s3_tools_dependencies_hash = var.deploy_s3_tools && fileexists(local.s3_tools_requirements) ? filemd5(local.s3_tools_requirements) : "missing"

  titanic_data_files = var.deploy_titanic_data ? fileset(local.titanic_data_path, "**") : []
  titanic_data_source_hash = var.deploy_titanic_data ? sha256(join("", [
    for f in local.titanic_data_files : filesha256("${local.titanic_data_path}/${f}")
  ])) : "not-deployed"
  titanic_data_dependencies_hash = var.deploy_titanic_data && fileexists(local.titanic_data_requirements) ? filemd5(local.titanic_data_requirements) : "missing"

  awscli_tools_files = var.deploy_awscli_tools ? fileset(local.awscli_tools_path, "**") : []
  awscli_tools_source_hash = var.deploy_awscli_tools ? sha256(join("", [
    for f in local.awscli_tools_files : filesha256("${local.awscli_tools_path}/${f}")
  ])) : "not-deployed"
  awscli_tools_dependencies_hash = var.deploy_awscli_tools && fileexists(local.awscli_tools_requirements) ? filemd5(local.awscli_tools_requirements) : "missing"

  # Package hashes (base64) for Lambda source_code_hash
  s3_tools_package_hash     = var.deploy_s3_tools ? base64sha256("${local.s3_tools_source_hash}:${local.s3_tools_dependencies_hash}") : "not-deployed"
  titanic_data_package_hash = var.deploy_titanic_data ? base64sha256("${local.titanic_data_source_hash}:${local.titanic_data_dependencies_hash}") : "not-deployed"
  awscli_tools_package_hash = var.deploy_awscli_tools ? base64sha256("${local.awscli_tools_source_hash}:${local.awscli_tools_dependencies_hash}") : "not-deployed"
}

# -----------------------------------------------------------------------------
# Stage 1 + 2: Build packages (deps + code) with hash triggers
# -----------------------------------------------------------------------------

resource "null_resource" "build_s3_tools" {
  count = var.deploy_s3_tools ? 1 : 0

  triggers = {
    dependencies_hash = local.s3_tools_dependencies_hash
    source_hash       = local.s3_tools_source_hash
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      echo "Building s3-tools package..."

      if [ ! -d "${local.s3_tools_path}" ]; then
        echo "ERROR: Source path not found: ${local.s3_tools_path}"
        exit 1
      fi
      if [ ! -f "${local.s3_tools_requirements}" ]; then
        echo "ERROR: Requirements file not found: ${local.s3_tools_requirements}"
        exit 1
      fi

      BUILD_DIR=$(mktemp -d)
      DEPS_DIR="$BUILD_DIR/deps"
      CODE_DIR="$BUILD_DIR/code"

      mkdir -p "$DEPS_DIR" "$CODE_DIR"

      if grep -Eq "^[a-zA-Z]" "${local.s3_tools_requirements}"; then
        pip install -t "$DEPS_DIR" -r <(grep -E "^[a-zA-Z]" "${local.s3_tools_requirements}")
      else
        echo "No dependencies to install for s3-tools"
      fi
      cp -r "${local.s3_tools_path}/"* "$CODE_DIR/"

      mkdir -p "${local.build_dir}"
      cd "$BUILD_DIR"
      zip -r "${local.build_dir}/s3-tools.zip" deps/ code/

      rm -rf "$BUILD_DIR"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "build_titanic_data" {
  count = var.deploy_titanic_data ? 1 : 0

  triggers = {
    dependencies_hash = local.titanic_data_dependencies_hash
    source_hash       = local.titanic_data_source_hash
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      echo "Building titanic-data package..."

      if [ ! -d "${local.titanic_data_path}" ]; then
        echo "ERROR: Source path not found: ${local.titanic_data_path}"
        exit 1
      fi
      if [ ! -f "${local.titanic_data_requirements}" ]; then
        echo "ERROR: Requirements file not found: ${local.titanic_data_requirements}"
        exit 1
      fi

      BUILD_DIR=$(mktemp -d)
      DEPS_DIR="$BUILD_DIR/deps"
      CODE_DIR="$BUILD_DIR/code"

      mkdir -p "$DEPS_DIR" "$CODE_DIR"

      if grep -Eq "^[a-zA-Z]" "${local.titanic_data_requirements}"; then
        pip install -t "$DEPS_DIR" -r <(grep -E "^[a-zA-Z]" "${local.titanic_data_requirements}")
      else
        echo "No dependencies to install for titanic-data"
      fi
      cp -r "${local.titanic_data_path}/"* "$CODE_DIR/"

      mkdir -p "${local.build_dir}"
      cd "$BUILD_DIR"
      zip -r "${local.build_dir}/titanic-data.zip" deps/ code/

      rm -rf "$BUILD_DIR"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "build_awscli_tools" {
  count = var.deploy_awscli_tools ? 1 : 0

  triggers = {
    dependencies_hash = local.awscli_tools_dependencies_hash
    source_hash       = local.awscli_tools_source_hash
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      echo "Building awscli-tools package..."

      if [ ! -d "${local.awscli_tools_path}" ]; then
        echo "ERROR: Source path not found: ${local.awscli_tools_path}"
        exit 1
      fi
      if [ ! -f "${local.awscli_tools_requirements}" ]; then
        echo "ERROR: Requirements file not found: ${local.awscli_tools_requirements}"
        exit 1
      fi

      BUILD_DIR=$(mktemp -d)
      DEPS_DIR="$BUILD_DIR/deps"
      CODE_DIR="$BUILD_DIR/code"

      mkdir -p "$DEPS_DIR" "$CODE_DIR"

      if grep -Eq "^[a-zA-Z]" "${local.awscli_tools_requirements}"; then
        pip install -t "$DEPS_DIR" -r <(grep -E "^[a-zA-Z]" "${local.awscli_tools_requirements}")
      else
        echo "No dependencies to install for awscli-tools"
      fi
      cp -r "${local.awscli_tools_path}/"* "$CODE_DIR/"

      mkdir -p "${local.build_dir}"
      cd "$BUILD_DIR"
      zip -r "${local.build_dir}/awscli-tools.zip" deps/ code/

      rm -rf "$BUILD_DIR"
    EOT
    interpreter = ["bash", "-c"]
  }
}

# -----------------------------------------------------------------------------
# Outputs for debugging
# -----------------------------------------------------------------------------

output "packaging_info" {
  description = "Packaging details for debugging"
  value = {
    s3_tools = var.deploy_s3_tools ? {
      source_path       = local.s3_tools_path
      source_hash       = local.s3_tools_source_hash
      package_hash      = local.s3_tools_package_hash
      package_path      = "${local.build_dir}/s3-tools.zip"
      requirements_file = local.s3_tools_requirements
    } : null
    titanic_data = var.deploy_titanic_data ? {
      source_path       = local.titanic_data_path
      source_hash       = local.titanic_data_source_hash
      package_hash      = local.titanic_data_package_hash
      package_path      = "${local.build_dir}/titanic-data.zip"
      requirements_file = local.titanic_data_requirements
    } : null
    awscli_tools = var.deploy_awscli_tools ? {
      source_path       = local.awscli_tools_path
      source_hash       = local.awscli_tools_source_hash
      package_hash      = local.awscli_tools_package_hash
      package_path      = "${local.build_dir}/awscli-tools.zip"
      requirements_file = local.awscli_tools_requirements
    } : null
  }
}
