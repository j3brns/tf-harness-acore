# LangGraph Baseline Example (Minimal)
# Runtime-only baseline for framework parity and local smoke testing

agent_name  = "langgraph-demo-core-k1l2"
app_id      = "langgraph-baseline"
region      = "us-east-1"
environment = "dev"

tags = {
  Team    = "Platform"
  Purpose = "Demo"
  Example = "6-langgraph-baseline"
}

# ===== FOUNDATION =====
enable_gateway       = false
enable_identity      = false
enable_observability = true
enable_xray          = true

# ===== TOOLS =====
enable_code_interpreter = false
enable_browser          = false

# ===== RUNTIME =====
enable_runtime      = true
runtime_source_path = "../examples/6-langgraph-baseline/agent-code"
runtime_entry_file  = "runtime.py"

runtime_config = {
  max_iterations  = 3
  timeout_seconds = 60
  framework       = "langgraph"
}

enable_memory = false

enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
enable_policy_engine = false
enable_evaluations   = false
