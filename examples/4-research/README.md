# Example 4: Research Agent (Simple)

A simplified research agent demonstrating MCP gateway integration with research tools.

## What This Example Shows

- MCP gateway integration with research APIs
- Code interpreter for data analysis
- Web browser for paper access
- Short-term and long-term memory
- Quality evaluation with Claude

## Features Enabled

| Feature | Status | Notes |
|---------|--------|-------|
| Gateway | Enabled | HYBRID search |
| Code Interpreter | Enabled | SANDBOX mode |
| Browser | Enabled | SANDBOX mode |
| Memory | Enabled | SHORT_TERM + LONG_TERM |
| Evaluations | Enabled | REASONING type |

## Prerequisites

Before deploying, you must:

1. **Deploy MCP Lambda functions** for ArXiv and PubMed
2. **Update tfvars** with your AWS account ID:
   ```hcl
   mcp_targets = {
     arxiv = {
       lambda_arn = "arn:aws:lambda:us-east-1:YOUR_ACCOUNT_ID:function:arxiv-mcp"
     }
     pubmed = {
       lambda_arn = "arn:aws:lambda:us-east-1:YOUR_ACCOUNT_ID:function:pubmed-mcp"
     }
   }
   ```

## Usage

### Deploy to AWS

```bash
cd terraform
terraform init
terraform plan -var-file=examples/4-research/terraform.tfvars
terraform apply -var-file=examples/4-research/terraform.tfvars
```

## Difference from Example 3 (Deep Research)

This example provides a simpler starting point for building research agents.
For the full-featured Strands DeepAgents implementation, see `examples/3-deepresearch/`.

| Aspect | Example 3 (Deep) | Example 4 (Simple) |
|--------|------------------|-------------------|
| Framework | Strands DeepAgents | Basic BedrockAgentCore |
| Complexity | Production-ready | Learning/starting point |
| Multi-agent | Yes (subagents) | No |
| Citations | Auto-formatting | Manual |
