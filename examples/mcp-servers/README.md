# MCP Servers for Bedrock AgentCore

This directory contains Model Context Protocol (MCP) server implementations for use with AWS Bedrock AgentCore Gateway.

## Overview

MCP servers provide tools that agents can invoke through the AgentCore Gateway. Each server implements the MCP protocol and can be deployed as:

- **Lambda functions** (production) - Deployed to AWS, invoked via Gateway
- **Local server** (development) - Run locally for testing without AWS

## Available Servers

### 1. S3 Tools (`s3-tools/`)

Provides S3 bucket and object operations.

**Tools:**
- `list_buckets` - List accessible S3 buckets
- `list_objects` - List objects in a bucket
- `get_object` - Download object content
- `put_object` - Upload content to S3
- `get_object_metadata` - Get object metadata

**Use Case:** File storage, data retrieval, content management

### 2. Titanic Data (`titanic-data/`)

Serves the Titanic passenger dataset for analysis demonstrations.

**Tools:**
- `fetch_dataset` - Get full or partial dataset
- `get_schema` - Get column information
- `query` - Run filtered queries
- `get_statistics` - Get summary statistics

**Use Case:** Data analysis demos, testing code interpreter

### 3. Local Development (`local-dev/`)

Flask-based local server for development and testing.

**Tools:**
- `echo` - Echo messages (connectivity test)
- `store_value` / `get_value` - Key-value storage
- `add_memory` / `get_memory` - Conversation memory
- `calculate` - Simple math calculations
- `get_env` - Environment information

**Use Case:** Local testing without AWS, development

## Quick Start

### Option 1: Integrated Deployment (Recommended)

The recommended approach uses MCP servers as a Terraform submodule with automatic ARN resolution:

```bash
# See the integrated example
cd ../5-integrated
terraform init
terraform apply
```

This pattern:
- Deploys MCP servers + AgentCore in one command
- Automatically resolves ARNs (no hardcoding)
- Handles dependencies correctly

See `examples/5-integrated/` for the full example.

### Option 2: Local Development

```bash
# Install dependencies
cd local-dev
pip install -r requirements.txt

# Run server
python server.py

# Test
curl http://localhost:8080/health
curl http://localhost:8080/tools/list

# Call a tool
curl -X POST http://localhost:8080/tools/call \
  -H "Content-Type: application/json" \
  -d '{"params": {"name": "echo", "arguments": {"message": "Hello!"}}}'
```

### Local Development Loop (Full Workflow)

Complete workflow for developing and testing MCP servers locally before deployment:

```bash
# 1. Setup (one-time)
make setup

# 2. Start local MCP server (Terminal 1)
make dev
# Server runs at http://localhost:8080

# 3. Develop and test (Terminal 2)
# Edit your handler code, then test:
make test-s3       # Test S3 tools handler
make test-titanic  # Test Titanic data handler
make test          # Run all tests

# 4. Validate Terraform (no AWS needed)
make validate

# 5. Deploy when ready
make plan          # Preview changes
make deploy        # Apply to AWS
```

**Development Cycle:**

```
┌─────────────────────────────────────────────────────────────┐
│                    LOCAL DEVELOPMENT                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Edit Code                    2. Test Locally            │
│     s3-tools/handler.py             make test-s3            │
│     titanic-data/handler.py         make test-titanic       │
│                                                             │
│  3. Test with Local Server       4. Validate Terraform      │
│     make dev                        make validate           │
│     curl localhost:8080/...                                 │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    AWS DEPLOYMENT                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  5. Plan                         6. Deploy                  │
│     make plan                       make deploy             │
│                                                             │
│  7. Test Lambda                  8. Rollback (if needed)    │
│     aws lambda invoke ...           Alias → previous ver    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Key Files:**

| File | Purpose |
|------|---------|
| `Makefile` | All dev commands |
| `scripts/test-local.sh` | Comprehensive test script |
| `local-dev/server.py` | Local Flask MCP server |
| `terraform/packaging.tf` | Two-stage Lambda build |

### Option 3: Standalone MCP Server Deployment

Deploy MCP servers separately, then reference outputs:

```bash
# Deploy MCP servers
cd terraform
terraform init
terraform apply

# Get ARNs for use in agent config
terraform output mcp_targets
```

### Using MCP Servers in AgentCore

**Recommended: Module Composition (Automatic ARNs)**

```hcl
# Deploy MCP servers as submodule
module "mcp_servers" {
  source = "./examples/mcp-servers/terraform"
  environment = var.environment
}

# Use outputs directly - no hardcoded ARNs!
module "agentcore" {
  source = "./"

  mcp_targets = module.mcp_servers.mcp_targets

  depends_on = [module.mcp_servers]
}
```

**Alternative: Manual ARN Reference**

If you deploy MCP servers separately:

```hcl
# After: cd examples/mcp-servers/terraform && terraform apply
# Run: terraform output mcp_targets
# Then use the output ARNs:

mcp_targets = {
  s3_tools = {
    name        = "s3-tools"
    lambda_arn  = "arn:aws:lambda:us-east-1:YOUR_ACCOUNT:function:agentcore-mcp-s3-tools-dev"
    description = "S3 bucket and object operations"
  }
}

## MCP Protocol

All servers implement the MCP JSON-RPC protocol:

### List Tools

```json
// Request
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": "1"
}

// Response
{
  "jsonrpc": "2.0",
  "result": {
    "tools": [
      {
        "name": "tool_name",
        "description": "Tool description",
        "inputSchema": {
          "type": "object",
          "properties": {...}
        }
      }
    ]
  },
  "id": "1"
}
```

### Call Tool

```json
// Request
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "tool_name",
    "arguments": {
      "param1": "value1"
    }
  },
  "id": "2"
}

// Response
{
  "jsonrpc": "2.0",
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"success\": true, ...}"
      }
    ]
  },
  "id": "2"
}
```

### Simple Format (Lambda Direct)

Servers also accept a simplified format for direct Lambda invocation:

```json
// Request
{
  "tool": "tool_name",
  "parameters": {
    "param1": "value1"
  }
}

// Response
{
  "statusCode": 200,
  "body": "{\"success\": true, ...}"
}
```

## Directory Structure

```
mcp-servers/
├── README.md              # This file
├── local-dev/             # Local development server
│   ├── server.py          # Flask MCP server
│   └── requirements.txt   # Python dependencies
├── s3-tools/              # S3 operations server
│   └── handler.py         # Lambda handler
├── titanic-data/          # Titanic dataset server
│   └── handler.py         # Lambda handler
└── terraform/             # Deployment module
    └── main.tf            # Lambda deployment
```

## Creating Custom MCP Servers

### Lambda Template

```python
"""
Custom MCP Server Template
"""

import json
import logging
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def tool_my_tool(params: dict) -> dict:
    """
    Your tool implementation.

    Parameters:
        param1: Description (required)
        param2: Description (optional)
    """
    param1 = params.get("param1")
    if not param1:
        return {"success": False, "error": "param1 required"}

    # Your logic here
    result = do_something(param1)

    return {
        "success": True,
        "result": result
    }


TOOLS = {
    "my_tool": {
        "handler": tool_my_tool,
        "description": "My tool description",
        "parameters": {
            "param1": "Description (required)",
            "param2": "Description"
        }
    }
}


def lambda_handler(event: dict, context: Any) -> dict:
    """Lambda handler for MCP tool invocation."""
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Handle MCP protocol format
        if "jsonrpc" in event:
            method = event.get("method", "")
            request_id = event.get("id")

            if method == "tools/list":
                tools_list = [
                    {
                        "name": name,
                        "description": info["description"],
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                k: {"type": "string", "description": v}
                                for k, v in info["parameters"].items()
                            },
                            "required": [
                                k for k, v in info["parameters"].items()
                                if "required" in v.lower()
                            ]
                        }
                    }
                    for name, info in TOOLS.items()
                ]
                return {
                    "jsonrpc": "2.0",
                    "result": {"tools": tools_list},
                    "id": request_id
                }

            elif method == "tools/call":
                params = event.get("params", {})
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})

                if tool_name not in TOOLS:
                    return {
                        "jsonrpc": "2.0",
                        "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"},
                        "id": request_id
                    }

                result = TOOLS[tool_name]["handler"](tool_args)
                return {
                    "jsonrpc": "2.0",
                    "result": {"content": [{"type": "text", "text": json.dumps(result)}]},
                    "id": request_id
                }

        # Handle simple format
        tool_name = event.get("tool", event.get("action"))
        tool_params = event.get("parameters", event.get("params", {}))

        if not tool_name:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "tool parameter required"})
            }

        if tool_name not in TOOLS:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": f"Unknown tool: {tool_name}"})
            }

        result = TOOLS[tool_name]["handler"](tool_params)
        return {
            "statusCode": 200,
            "body": json.dumps(result)
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
```

## Testing

### Test Local Server

```bash
# Start server
cd local-dev
python server.py &

# Run tests
curl http://localhost:8080/tools/list | jq .
curl -X POST http://localhost:8080/tools/call \
  -H "Content-Type: application/json" \
  -d '{"params": {"name": "echo", "arguments": {"message": "test"}}}' | jq .
```

### Test Lambda Locally

```bash
# Test with sample event
cd s3-tools
python -c "
import handler
result = handler.lambda_handler({
    'tool': 'list_buckets',
    'parameters': {}
}, None)
print(result)
"
```

### Test Deployed Lambda

```bash
# Invoke via AWS CLI
aws lambda invoke \
  --function-name agentcore-mcp-s3-tools-dev \
  --payload '{"tool": "list_buckets", "parameters": {}}' \
  response.json

cat response.json | jq .
```

## Security Considerations

1. **IAM Permissions**: Lambda roles have minimal permissions. S3 tools only access allowed buckets.

2. **Input Validation**: All tool inputs are validated before use.

3. **Error Handling**: Errors return sanitized messages, no stack traces.

4. **Logging**: CloudWatch logs for auditing, configurable retention.

5. **No Credentials in Code**: Use IAM roles, not embedded credentials.

## Troubleshooting

### Lambda Not Invoking

```bash
# Check Lambda exists
aws lambda get-function --function-name agentcore-mcp-s3-tools-dev

# Check CloudWatch logs
aws logs tail /aws/lambda/agentcore-mcp-s3-tools-dev --follow
```

### Permission Denied

```bash
# Check IAM role policies
aws iam get-role-policy --role-name agentcore-mcp-lambda-role-dev --policy-name agentcore-mcp-s3-access-policy
```

### Local Server Connection Refused

```bash
# Check if server is running
lsof -i :8080

# Restart server
python server.py
```
