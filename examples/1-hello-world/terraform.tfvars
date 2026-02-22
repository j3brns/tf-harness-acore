# Hello World S3 Explorer Agent
# Minimal configuration demonstrating basic AgentCore capabilities

agent_name  = "hello-world-s3-a1b2"
app_id      = "hello-world-s3"
region      = "eu-west-2"
environment = "dev"

tags = {
  Team    = "Platform"
  Purpose = "Demo"
  Example = "1-hello-world"
}

# ===== FOUNDATION =====
# Gateway disabled - this is a standalone agent
enable_gateway       = false
enable_identity      = false
enable_observability = true
enable_xray          = true
# Note: Using AWS-managed encryption (SSE-S3) - no customer KMS needed

# ===== TOOLS =====
# No tools needed for this simple example
enable_code_interpreter = false
enable_browser          = false

# ===== RUNTIME =====
enable_runtime      = true
runtime_source_path = "../examples/1-hello-world/agent-code"
runtime_entry_file  = "runtime.py"

runtime_config = {
  max_iterations  = 1
  timeout_seconds = 30
}

# No memory needed for stateless operation
enable_memory = false

# Enable packaging for dependency management
enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
# No governance for this simple example
enable_policy_engine = false
enable_evaluations   = false
