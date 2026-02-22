# Research Agent (Simple Example)
# Basic research agent demonstrating gateway and code interpreter

agent_name  = "research-agent-core-g7h8"
app_id      = "research-agent"
region      = "eu-west-2"
environment = "dev"

tags = {
  Team    = "Research"
  Purpose = "Example"
  Example = "4-research"
}

# ===== FOUNDATION =====
enable_gateway      = true
gateway_name        = "deep-research-gateway"
gateway_search_type = "HYBRID"

# MCP Targets - Research tool integrations
# NOTE: Replace ACCOUNT_ID with your actual AWS account ID before deployment
mcp_targets = {
  arxiv = {
    name = "arxiv-search"
    # IMPORTANT: Replace with your actual AWS account ID
    lambda_arn  = "arn:aws:lambda:eu-west-2:111122223333:function:arxiv-mcp"
    description = "ArXiv paper search"
  }
  pubmed = {
    name = "pubmed-search"
    # IMPORTANT: Replace with your actual AWS account ID
    lambda_arn  = "arn:aws:lambda:eu-west-2:111122223333:function:pubmed-mcp"
    description = "PubMed literature search"
  }
}

enable_identity      = false
enable_observability = true
enable_xray          = true
# Note: Using AWS-managed encryption (SSE-S3) - no customer KMS needed

# ===== TOOLS =====
# Code interpreter for data analysis
enable_code_interpreter       = true
code_interpreter_network_mode = "SANDBOX"

# Browser for accessing research papers
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

# Long-term memory for knowledge retention
enable_memory = true
memory_type   = "BOTH" # Both short-term and long-term

# Packaging
enable_packaging = true
python_version   = "3.12"

# ===== GOVERNANCE =====
# Policy engine for research integrity
enable_policy_engine = false # Enable if Cedar policies are configured

# Quality evaluation for research output
enable_evaluations = true
evaluation_type    = "REASONING"
evaluator_model_id = "anthropic.claude-sonnet-4-5"
evaluation_prompt  = "Evaluate the research quality, accuracy, and relevance of findings."

evaluation_criteria = {
  research_quality = "Quality and rigor of research methodology"
  accuracy         = "Factual accuracy of citations and findings"
  relevance        = "Relevance to the research question"
  completeness     = "Comprehensiveness of literature coverage"
  clarity          = "Clarity and organization of presentation"
}
