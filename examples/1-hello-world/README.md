# Example 1: Hello World S3 Explorer

A minimal agent demonstrating basic Bedrock AgentCore capabilities.

## What This Example Shows

- Basic agent runtime structure
- AWS SDK usage (boto3)
- Structured JSON output
- Error handling patterns

## Features Enabled

| Feature | Status | Notes |
|---------|--------|-------|
| Gateway | Disabled | Standalone agent |
| Code Interpreter | Disabled | Not needed |
| Browser | Disabled | Not needed |
| Memory | Disabled | Stateless operation |
| Policy Engine | Disabled | No governance |
| Evaluations | Disabled | No quality checks |

## Agent Code

The agent:
1. Connects to S3 using boto3
2. Lists available buckets
3. Returns first 5 bucket names with creation dates
4. Handles errors gracefully

## Usage

### Local Testing

```bash
cd examples/1-hello-world/agent-code
python runtime.py
```

### Deploy to AWS

```bash
cd terraform
terraform init
terraform plan -var-file=examples/1-hello-world/terraform.tfvars
terraform apply -var-file=examples/1-hello-world/terraform.tfvars
```

## Expected Output

```json
{
  "status": "success",
  "message": "Hello from Bedrock AgentCore!",
  "timestamp": "2024-01-01T00:00:00Z",
  "data": {
    "bucket_count": 5,
    "buckets": [
      {"name": "my-bucket-1", "created": "2023-01-01T00:00:00Z"},
      {"name": "my-bucket-2", "created": "2023-06-15T00:00:00Z"}
    ],
    "truncated": false
  }
}
```

## Cost Estimate

This minimal example costs approximately:
- Runtime: ~$0.01/execution
- CloudWatch Logs: ~$0.01/day
- S3 (deployment): ~$0.01/month

**Monthly estimate**: < $1 for low usage
