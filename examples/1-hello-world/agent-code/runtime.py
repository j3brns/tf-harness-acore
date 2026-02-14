"""
Hello World S3 Explorer Agent

A minimal agent demonstrating basic Bedrock AgentCore capabilities.
Lists S3 buckets and returns a summary.

Features demonstrated:
- Basic runtime structure
- AWS SDK usage (boto3)
- Structured JSON output
- Error handling
"""

import json
import logging
from datetime import datetime, UTC

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def handler(event, context):
    """
    Main handler for the Hello World agent.

    Args:
        event: Input event from Bedrock AgentCore
        context: Lambda context (if running in Lambda)

    Returns:
        dict: Agent response with bucket information
    """
    logger.info("Hello World agent invoked")
    logger.info(f"Event: {json.dumps(event)}")

    try:
        # Import boto3 here to allow local testing without it
        import boto3

        s3 = boto3.client("s3")

        # List buckets
        response = s3.list_buckets()
        buckets = response.get("Buckets", [])

        # Build response
        result = {
            "status": "success",
            "message": "Hello from Bedrock AgentCore!",
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "data": {
                "bucket_count": len(buckets),
                "buckets": [
                    {"name": bucket["Name"], "created": bucket["CreationDate"].isoformat()}
                    for bucket in buckets[:5]  # First 5 buckets
                ],
                "truncated": len(buckets) > 5,
            },
        }

        logger.info(f"Found {len(buckets)} buckets")
        return result

    except ImportError:
        # boto3 not available (local testing without AWS SDK)
        return {
            "status": "success",
            "message": "Hello from Bedrock AgentCore! (demo mode - boto3 not available)",
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "data": {"bucket_count": 0, "buckets": [], "demo_mode": True},
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "status": "error",
            "message": f"Failed to list buckets: {str(e)}",
            "timestamp": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }


# Allow local testing
if __name__ == "__main__":
    # Test event
    test_event = {"action": "list_buckets"}

    result = handler(test_event, None)
    print(json.dumps(result, indent=2, default=str))
