# Deep Research Agent - Full-Featured Example
# Uses Strands DeepAgents with internet search capabilities

agent_name  = "deep-research-agent-e5f6"
app_id      = "deep-research"
region      = "eu-west-2"
environment = "dev"

# Runtime configuration
enable_runtime      = true
runtime_source_path = "../examples/3-deepresearch/agent-code"
runtime_entry_file  = "runtime.py"

# Gateway for MCP tools (internet search uses external API)
enable_gateway = true

# MCP targets - add your search API Lambda here
# mcp_targets = {
#   search = {
#     name        = "internet-search-api"
#     lambda_arn  = "arn:aws:lambda:eu-west-2:YOUR_ACCOUNT:function:linkup-search-mcp"
#     description = "Linkup SDK internet search integration"
#   }
# }

# Code interpreter for data analysis
enable_code_interpreter       = true
code_interpreter_network_mode = "SANDBOX"

# Browser for web research
enable_browser       = true
browser_network_mode = "SANDBOX"

# Memory for session persistence
enable_memory = true
memory_type   = "BOTH"

# Observability
enable_observability = true
log_retention_days   = 30

# Tags
tags = {
  Project     = "deep-research-agent"
  Example     = "3-deepresearch"
  Description = "Full-featured research agent with Strands DeepAgents"
}
