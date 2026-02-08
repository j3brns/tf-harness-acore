# Example 2: Gateway Tool - Titanic Data Analysis

Demonstrates MCP gateway integration with code interpreter for data analysis.

## What This Example Shows

- MCP gateway configuration
- Lambda-based MCP tool integration
- Code interpreter for pandas analysis
- Multi-step agent workflow

## Features Enabled

| Feature | Status | Notes |
|---------|--------|-------|
| Gateway | Enabled | MCP protocol |
| Code Interpreter | Enabled | SANDBOX mode |
| Browser | Disabled | Not needed |
| Memory | Disabled | Stateless analysis |
| Policy Engine | Disabled | No governance |
| Evaluations | Disabled | No quality checks |

## Architecture

```
User Request
     |
     v
+--------------------+
| Titanic Analyzer   |
| (Agent Runtime)    |
+--------------------+
     |
     v
+--------------------+      +--------------------+
| MCP Gateway        | ---> | Titanic MCP Lambda |
+--------------------+      +--------------------+
     |                            |
     v                            v
+--------------------+      Titanic Dataset
| Code Interpreter   |      (GitHub CSV)
| (pandas analysis)  |
+--------------------+
     |
     v
Analysis Results
```

## Components

### 1. Agent Runtime (`agent-code/runtime.py`)
Main agent that orchestrates the workflow:
1. Fetches dataset via MCP tool
2. Analyzes survival rates with pandas
3. Generates insights

### 2. MCP Lambda (`lambda/titanic-mcp/index.py`)
Lambda function that provides the Titanic dataset:
- `fetch`: Download and return dataset
- `schema`: Return column information
- `sample`: Return small sample for testing

## Prerequisites

Before deploying, you must:

1. **Deploy the MCP Lambda** (manually or via separate Terraform):
   ```bash
   cd examples/2-gateway-tool/lambda/titanic-mcp
   zip function.zip index.py
   aws lambda create-function \
     --function-name titanic-mcp \
     --runtime python3.12 \
     --handler index.lambda_handler \
     --zip-file fileb://function.zip \
     --role arn:aws:iam::${ACCOUNT_ID}:role/lambda-execution-role
   ```

2. **Update the tfvars** with your account ID:
   ```hcl
   mcp_targets = {
     titanic_dataset = {
       lambda_arn = "arn:aws:lambda:us-east-1:YOUR_ACCOUNT_ID:function:titanic-mcp"
     }
   }
   ```

## Usage

### Local Testing

```bash
# Test agent
cd examples/2-gateway-tool/agent-code
python runtime.py

# Test Lambda
cd examples/2-gateway-tool/lambda/titanic-mcp
python index.py
```

### Deploy to AWS

```bash
cd terraform

# First deploy Lambda (or use existing)
# Then deploy agent
terraform init
terraform plan -var-file=examples/2-gateway-tool/terraform.tfvars
terraform apply -var-file=examples/2-gateway-tool/terraform.tfvars
```

## Expected Output

```json
{
  "status": "success",
  "message": "Titanic survival analysis complete",
  "analysis": {
    "total_passengers": 891,
    "survivors": 342,
    "overall_survival_rate": 0.384,
    "survival_by_class": {
      "1": 0.63,
      "2": 0.47,
      "3": 0.24
    },
    "survival_by_gender": {
      "female": 0.74,
      "male": 0.19
    }
  },
  "insights": [
    "Overall survival rate was 38.4%",
    "First class passengers had 63.0% survival rate",
    "Third class passengers had 24.2% survival rate",
    "Women survived at 74.2% vs men at 18.9%"
  ]
}
```

## Cost Estimate

| Component | Cost |
|-----------|------|
| Gateway | ~$0.001/request |
| Lambda | ~$0.0001/invocation |
| Code Interpreter | ~$0.001/second |
| CloudWatch | ~$0.01/day |

**Monthly estimate**: $5-10 for moderate usage
