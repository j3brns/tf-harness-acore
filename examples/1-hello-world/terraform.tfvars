# Hello World Strands Baseline Agent
# Minimal configuration demonstrating Strands single-agent baseline parity

agent_name  = "hello-world-strands-a1b2"
app_id      = "hello-world-strands"
region      = "us-east-1"
environment = "dev"

tags = {
  Team    = "Platform"
  Purpose = "Demo"
  Example = "1-hello-world"
}

# ===== FOUNDATION =====
# Gateway disabled - this is a standalone baseline agent
enable_gateway       = false
enable_identity      = false
enable_observability = true
enable_xray          = true
# Note: Using AWS-managed encryption (SSE-S3) - no customer KMS needed

# ===== TOOLS =====
# No managed AgentCore tools for this baseline example (uses local Strands demo tools)
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

# No memory needed for this baseline parity example
enable_memory = false

# Enable packaging for dependency management
enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
# No governance for this baseline example
enable_policy_engine = false
enable_evaluations   = false
