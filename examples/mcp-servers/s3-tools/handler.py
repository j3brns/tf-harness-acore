"""
S3 Tools MCP Server

A Lambda-based MCP server providing S3 operations for Bedrock AgentCore agents.
Implements the MCP protocol for tool invocation from Gateway.

Tools provided:
- list_buckets: List all S3 buckets
- list_objects: List objects in a bucket
- get_object: Get object content
- put_object: Upload content to S3
- get_object_metadata: Get object metadata
"""

import json
import logging
import base64
from typing import Any
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')


def json_serial(obj):
    """JSON serializer for objects not serializable by default."""
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


def tool_list_buckets(params: dict) -> dict:
    """List all S3 buckets accessible by this Lambda."""
    try:
        response = s3_client.list_buckets()

        buckets = [
            {
                "name": bucket["Name"],
                "creation_date": bucket["CreationDate"].isoformat()
            }
            for bucket in response.get("Buckets", [])
        ]

        # Optional: filter by prefix
        prefix = params.get("prefix")
        if prefix:
            buckets = [b for b in buckets if b["name"].startswith(prefix)]

        return {
            "success": True,
            "count": len(buckets),
            "buckets": buckets
        }

    except ClientError as e:
        return {
            "success": False,
            "error": str(e),
            "error_code": e.response["Error"]["Code"]
        }


def tool_list_objects(params: dict) -> dict:
    """
    List objects in an S3 bucket.

    Parameters:
        bucket: Bucket name (required)
        prefix: Object prefix filter
        max_keys: Maximum objects to return (default: 100)
        delimiter: Delimiter for hierarchy
    """
    bucket = params.get("bucket")
    if not bucket:
        return {"success": False, "error": "bucket parameter required"}

    try:
        list_params = {
            "Bucket": bucket,
            "MaxKeys": params.get("max_keys", 100)
        }

        if params.get("prefix"):
            list_params["Prefix"] = params["prefix"]
        if params.get("delimiter"):
            list_params["Delimiter"] = params["delimiter"]

        response = s3_client.list_objects_v2(**list_params)

        objects = [
            {
                "key": obj["Key"],
                "size": obj["Size"],
                "last_modified": obj["LastModified"].isoformat(),
                "storage_class": obj.get("StorageClass", "STANDARD")
            }
            for obj in response.get("Contents", [])
        ]

        # Include common prefixes (folders) if delimiter was used
        prefixes = [
            {"prefix": cp["Prefix"]}
            for cp in response.get("CommonPrefixes", [])
        ]

        return {
            "success": True,
            "bucket": bucket,
            "object_count": len(objects),
            "is_truncated": response.get("IsTruncated", False),
            "objects": objects,
            "common_prefixes": prefixes
        }

    except ClientError as e:
        return {
            "success": False,
            "error": str(e),
            "error_code": e.response["Error"]["Code"]
        }


def tool_get_object(params: dict) -> dict:
    """
    Get object content from S3.

    Parameters:
        bucket: Bucket name (required)
        key: Object key (required)
        encoding: How to return content - 'text', 'base64', 'json' (default: text)
        max_size: Maximum size to read in bytes (default: 1MB)
    """
    bucket = params.get("bucket")
    key = params.get("key")

    if not bucket or not key:
        return {"success": False, "error": "bucket and key parameters required"}

    max_size = params.get("max_size", 1024 * 1024)  # 1MB default
    encoding = params.get("encoding", "text")

    try:
        # First check object size
        head = s3_client.head_object(Bucket=bucket, Key=key)
        size = head["ContentLength"]

        if size > max_size:
            return {
                "success": False,
                "error": f"Object too large: {size} bytes (max: {max_size})",
                "size": size,
                "content_type": head.get("ContentType")
            }

        # Get object
        response = s3_client.get_object(Bucket=bucket, Key=key)
        body = response["Body"].read()

        # Encode content based on requested format
        if encoding == "base64":
            content = base64.b64encode(body).decode("utf-8")
        elif encoding == "json":
            content = json.loads(body.decode("utf-8"))
        else:
            content = body.decode("utf-8", errors="replace")

        return {
            "success": True,
            "bucket": bucket,
            "key": key,
            "size": size,
            "content_type": response.get("ContentType"),
            "last_modified": response["LastModified"].isoformat(),
            "encoding": encoding,
            "content": content
        }

    except ClientError as e:
        return {
            "success": False,
            "error": str(e),
            "error_code": e.response["Error"]["Code"]
        }


def tool_put_object(params: dict) -> dict:
    """
    Upload content to S3.

    Parameters:
        bucket: Bucket name (required)
        key: Object key (required)
        content: Content to upload (required)
        content_type: MIME type (default: text/plain)
        encoding: Content encoding - 'text' or 'base64' (default: text)
    """
    bucket = params.get("bucket")
    key = params.get("key")
    content = params.get("content")

    if not bucket or not key or content is None:
        return {"success": False, "error": "bucket, key, and content parameters required"}

    content_type = params.get("content_type", "text/plain")
    encoding = params.get("encoding", "text")

    try:
        # Decode content if base64
        if encoding == "base64":
            body = base64.b64decode(content)
        elif isinstance(content, dict):
            body = json.dumps(content).encode("utf-8")
            content_type = "application/json"
        else:
            body = content.encode("utf-8")

        response = s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType=content_type
        )

        return {
            "success": True,
            "bucket": bucket,
            "key": key,
            "size": len(body),
            "etag": response.get("ETag", "").strip('"'),
            "version_id": response.get("VersionId")
        }

    except ClientError as e:
        return {
            "success": False,
            "error": str(e),
            "error_code": e.response["Error"]["Code"]
        }


def tool_get_object_metadata(params: dict) -> dict:
    """
    Get object metadata without downloading content.

    Parameters:
        bucket: Bucket name (required)
        key: Object key (required)
    """
    bucket = params.get("bucket")
    key = params.get("key")

    if not bucket or not key:
        return {"success": False, "error": "bucket and key parameters required"}

    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)

        return {
            "success": True,
            "bucket": bucket,
            "key": key,
            "size": response["ContentLength"],
            "content_type": response.get("ContentType"),
            "last_modified": response["LastModified"].isoformat(),
            "etag": response.get("ETag", "").strip('"'),
            "storage_class": response.get("StorageClass", "STANDARD"),
            "metadata": response.get("Metadata", {}),
            "version_id": response.get("VersionId")
        }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "404":
            return {
                "success": False,
                "error": "Object not found",
                "error_code": "NotFound"
            }
        return {
            "success": False,
            "error": str(e),
            "error_code": error_code
        }


# Tool registry
TOOLS = {
    "list_buckets": {
        "handler": tool_list_buckets,
        "description": "List S3 buckets",
        "parameters": {
            "prefix": "Optional bucket name prefix filter"
        }
    },
    "list_objects": {
        "handler": tool_list_objects,
        "description": "List objects in a bucket",
        "parameters": {
            "bucket": "Bucket name (required)",
            "prefix": "Object key prefix filter",
            "max_keys": "Maximum objects to return",
            "delimiter": "Delimiter for hierarchy"
        }
    },
    "get_object": {
        "handler": tool_get_object,
        "description": "Get object content from S3",
        "parameters": {
            "bucket": "Bucket name (required)",
            "key": "Object key (required)",
            "encoding": "Content encoding: text, base64, json",
            "max_size": "Maximum size to read in bytes"
        }
    },
    "put_object": {
        "handler": tool_put_object,
        "description": "Upload content to S3",
        "parameters": {
            "bucket": "Bucket name (required)",
            "key": "Object key (required)",
            "content": "Content to upload (required)",
            "content_type": "MIME type",
            "encoding": "Content encoding: text or base64"
        }
    },
    "get_object_metadata": {
        "handler": tool_get_object_metadata,
        "description": "Get object metadata",
        "parameters": {
            "bucket": "Bucket name (required)",
            "key": "Object key (required)"
        }
    }
}


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Lambda handler for MCP tool invocation.

    Supports both simple format and MCP protocol format.
    """
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
                            "required": [k for k, v in info["parameters"].items() if "required" in v.lower()]
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
                    "result": {"content": [{"type": "text", "text": json.dumps(result, default=json_serial)}]},
                    "id": request_id
                }

        # Handle simple format
        tool_name = event.get("tool", event.get("action"))
        tool_params = event.get("parameters", event.get("params", {}))

        if not tool_name:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "tool parameter required", "available": list(TOOLS.keys())})
            }

        if tool_name not in TOOLS:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": f"Unknown tool: {tool_name}", "available": list(TOOLS.keys())})
            }

        result = TOOLS[tool_name]["handler"](tool_params)

        return {
            "statusCode": 200,
            "body": json.dumps(result, default=json_serial)
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }


# Local testing (requires AWS credentials)
if __name__ == "__main__":
    print("=== List Buckets ===")
    result = lambda_handler({"tool": "list_buckets", "parameters": {}}, None)
    print(json.dumps(json.loads(result["body"]), indent=2))
