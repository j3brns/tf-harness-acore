# Gateway Tool Agent - Titanic Data Analysis
# Demonstrates MCP gateway with code interpreter

agent_name  = "titanic-data-analyzer-c3d4"
app_id      = "titanic-analyzer"
region      = "us-east-1"
environment = "dev"

tags = {
  Team    = "Data Science"
  Purpose = "Demo"
  Example = "2-gateway-tool"
}

# ===== FOUNDATION =====
enable_gateway      = true
gateway_name        = "titanic-analyzer-gateway"
gateway_search_type = "SEMANTIC"

# MCP Target - Lambda providing Titanic dataset
#
# DEPLOYMENT OPTIONS:
# 1. Deploy MCP servers first:
#    cd examples/mcp-servers/terraform
#    terraform apply
#    Then use the output ARNs below
#
# 2. Or manually replace ACCOUNT_ID with your AWS account ID
#
# NOTE: Replace 999999999999 with your actual AWS account ID before deployment
mcp_targets = {
  titanic_dataset = {
    name = "titanic-dataset-tool"
    # IMPORTANT: Replace with output from: cd examples/mcp-servers/terraform && terraform output titanic_data_lambda_arn
    lambda_arn  = "arn:aws:lambda:us-east-1:111122223333:function:agentcore-mcp-titanic-data-dev"
    description = "Provides Titanic dataset for survival analysis"
  }
}

enable_identity      = false
enable_observability = true
enable_xray          = true
# Note: Using AWS-managed encryption (SSE-S3) - no customer KMS needed

# ===== TOOLS =====
# Code interpreter for pandas analysis
enable_code_interpreter       = true
code_interpreter_network_mode = "SANDBOX"

# No browser needed
enable_browser = false

# ===== RUNTIME =====
enable_runtime      = true
runtime_source_path = "../examples/2-gateway-tool/agent-code"
runtime_entry_file  = "runtime.py"

runtime_config = {
  max_iterations  = 5
  timeout_seconds = 120
  analysis_type   = "survival"
}

# No memory needed - stateless analysis
enable_memory = false

# Enable packaging for pandas dependency
enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
# No governance for this example
enable_policy_engine = false
enable_evaluations   = false
