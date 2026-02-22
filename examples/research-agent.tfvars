# Example configuration for a Research Agent
# Includes web browsing, code analysis, and memory for long-term learning

region      = "eu-west-2"
environment = "prod"
agent_name  = "research-agent-core-prod-j9k0"
app_id      = "research-agent"

tags = {
  Team    = "Research"
  Owner   = "research-team@example.com"
  Purpose = "Data research and analysis"
}

# ===== FOUNDATION =====
enable_gateway      = true
gateway_name        = "research-agent-gateway"
gateway_search_type = "HYBRID"

# MCP Targets - Custom Lambda tools for research
#
# IMPORTANT: These are example placeholder ARNs. You must either:
# 1. Create your own arxiv/pubmed Lambda MCP servers using the template in examples/mcp-servers/
# 2. Use the included MCP servers (s3-tools, titanic-data) instead
# 3. Replace 123456789012 with your actual AWS account ID and create the Lambda functions
#
# To deploy included MCP servers:
#   cd examples/mcp-servers/terraform
#   terraform apply
#
mcp_targets = {}

# Example research tools (placeholder ARNs - replace or remove)
# mcp_targets = {
#   arxiv_search = {
#     name        = "arxiv-search-tool"
#     lambda_arn  = "arn:aws:lambda:eu-west-2:123456789012:function:arxiv-search-mcp"
#     description = "Search ArXiv for research papers"
#   }
#   pubmed_search = {
#     name        = "pubmed-search-tool"
#     lambda_arn  = "arn:aws:lambda:eu-west-2:123456789012:function:pubmed-search-mcp"
#     description = "Search PubMed for biomedical literature"
#   }
# }

enable_identity      = false
enable_observability = true
enable_xray          = true
# Note: Using AWS-managed encryption (SSE-S3) - no customer KMS needed

# ===== TOOLS =====
enable_code_interpreter       = true
code_interpreter_network_mode = "SANDBOX"

enable_browser           = true
browser_network_mode     = "SANDBOX"
enable_browser_recording = false

# ===== RUNTIME =====
enable_runtime      = true
runtime_source_path = "../examples/4-research/agent-code"
runtime_entry_file  = "runtime.py"

runtime_config = {
  max_iterations  = 20
  timeout_seconds = 600
  research_depth  = "comprehensive"
  citation_format = "ieee"
}

enable_memory = true
memory_type   = "BOTH"

enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
enable_policy_engine = false

enable_evaluations = true
evaluation_type    = "REASONING"
evaluation_prompt  = "Evaluate the research quality, accuracy, and relevance of findings."

evaluation_criteria = {
  research_quality = "Quality and rigor of research methodology"
  accuracy         = "Factual accuracy of citations and findings"
  relevance        = "Relevance to the research question"
  completeness     = "Comprehensiveness of literature coverage"
}
