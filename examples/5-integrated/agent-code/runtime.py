"""
Integrated Demo Agent

Demonstrates using both S3 tools and Titanic data MCP servers.
"""

import json
from typing import Any


def handler(event: dict, context: Any) -> dict:
    """
    Agent that combines S3 operations with Titanic data analysis.

    This agent can:
    1. List S3 buckets using the s3-tools MCP server
    2. Analyze Titanic survival data using the titanic-data MCP server
    3. Store analysis results back to S3
    """
    action = event.get("action", "analyze")

    if action == "list_buckets":
        # Would invoke s3-tools MCP: list_buckets
        return {
            "status": "success",
            "action": "list_buckets",
            "message": "Use Gateway to invoke s3-tools.list_buckets"
        }

    elif action == "analyze":
        # Would invoke titanic-data MCP: get_statistics
        return {
            "status": "success",
            "action": "analyze",
            "message": "Use Gateway to invoke titanic-data.get_statistics",
            "sample_analysis": {
                "dataset": "titanic",
                "survival_rate": 0.38,
                "insights": [
                    "First class passengers had 63% survival rate",
                    "Female passengers had 74% survival rate",
                    "Age was a significant factor in survival"
                ]
            }
        }

    elif action == "full_workflow":
        # Combined workflow:
        # 1. Get Titanic data
        # 2. Analyze with code interpreter
        # 3. Store results to S3
        return {
            "status": "success",
            "action": "full_workflow",
            "workflow_steps": [
                {"step": 1, "tool": "titanic-data.fetch_dataset", "status": "ready"},
                {"step": 2, "tool": "code-interpreter", "status": "ready"},
                {"step": 3, "tool": "s3-tools.put_object", "status": "ready"}
            ],
            "message": "Workflow ready - invoke via Gateway"
        }

    else:
        return {
            "status": "error",
            "message": f"Unknown action: {action}",
            "available_actions": ["list_buckets", "analyze", "full_workflow"]
        }


if __name__ == "__main__":
    # Test locally
    print("=== List Buckets ===")
    print(json.dumps(handler({"action": "list_buckets"}, None), indent=2))

    print("\n=== Analyze ===")
    print(json.dumps(handler({"action": "analyze"}, None), indent=2))

    print("\n=== Full Workflow ===")
    print(json.dumps(handler({"action": "full_workflow"}, None), indent=2))
