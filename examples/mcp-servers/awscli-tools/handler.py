"""
AWS CLI Tools MCP Server

Provides a 'run_command' tool that allows agents to execute AWS CLI-like operations.
"""

import json
import logging
import os
import boto3
from typing import Any
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def tool_run_command(params: dict) -> dict:
    """
    Execute an AWS operation.
    
    Parameters:
        service: AWS Service (e.g., 'ec2', 'iam')
        operation: API Operation (e.g., 'describe_instances')
        parameters: Dictionary of arguments for the operation
    """
    service = params.get("service")
    operation = params.get("operation")
    args = params.get("parameters", {})

    if not service or not operation:
        return {"success": False, "error": "service and operation parameters required"}

    try:
        client = boto3.client(service)
        # Convert CamelCase operation to snake_case if necessary, 
        # but boto3 expects snake_case for method calls.
        method = getattr(client, operation)
        response = method(**args)

        # Remove Metadata to keep output clean
        if "ResponseMetadata" in response:
            del response["ResponseMetadata"]

        return {"success": True, "result": response}

    except AttributeError:
        return {"success": False, "error": f"Operation '{operation}' not found for service '{service}'"}
    except ClientError as e:
        return {"success": False, "error": str(e), "error_code": e.response["Error"]["Code"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

TOOLS = {
    "run_command": {
        "handler": tool_run_command,
        "description": "Run a specific AWS API command",
        "parameters": {
            "service": "AWS service name (e.g., 's3', 'ec2')",
            "operation": "Boto3 method name (e.g., 'list_buckets', 'describe_instances')",
            "parameters": "Dictionary of arguments for the method"
        }
    }
}

def lambda_handler(event: dict, context: Any) -> dict:
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
                                k: {"type": "string", "description": v} for k, v in info["parameters"].items()
                            }
                        }
                    }
                    for name, info in TOOLS.items()
                ]
                return {"jsonrpc": "2.0", "result": {"tools": tools_list}, "id": request_id}

            elif method == "tools/call":
                params = event.get("params", {})
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})

                if tool_name not in TOOLS:
                    return {"jsonrpc": "2.0", "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"}, "id": request_id}

                result = TOOLS[tool_name]["handler"](tool_args)
                return {
                    "jsonrpc": "2.0",
                    "result": {"content": [{"type": "text", "text": json.dumps(result, default=str)}]},
                    "id": request_id
                }

        # Simple format fallback
        tool_name = event.get("tool")
        tool_params = event.get("parameters", {})
        if tool_name in TOOLS:
            return {"statusCode": 200, "body": json.dumps(TOOLS[tool_name]["handler"](tool_params), default=str)}
        
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid request"})}

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
