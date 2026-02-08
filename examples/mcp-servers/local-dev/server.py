"""
Local Development MCP Server

A Flask-based MCP server for local development and testing without AWS.
Simulates the MCP protocol locally for testing agent code before deployment.

Run: python server.py
Test: curl http://localhost:8080/tools/list
"""

import json
import logging
from flask import Flask, request, jsonify
from datetime import datetime
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Simulated local storage (in-memory)
LOCAL_STORAGE = {}
CONVERSATION_MEMORY = []


def json_serial(obj):
    """JSON serializer for objects not serializable by default."""
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


# =============================================================================
# Tool Implementations
# =============================================================================


def tool_echo(params: dict) -> dict:
    """Echo back the input - useful for testing connectivity."""
    return {
        "success": True,
        "echo": params.get("message", "Hello from local MCP server!"),
        "timestamp": datetime.now().isoformat(),
    }


def tool_store_value(params: dict) -> dict:
    """Store a key-value pair in local memory."""
    key = params.get("key")
    value = params.get("value")

    if not key:
        return {"success": False, "error": "key parameter required"}

    LOCAL_STORAGE[key] = {"value": value, "stored_at": datetime.now().isoformat()}

    return {"success": True, "key": key, "message": f"Value stored for key: {key}"}


def tool_get_value(params: dict) -> dict:
    """Retrieve a value from local memory."""
    key = params.get("key")

    if not key:
        return {"success": False, "error": "key parameter required"}

    if key not in LOCAL_STORAGE:
        return {"success": False, "error": f"Key not found: {key}"}

    return {
        "success": True,
        "key": key,
        "value": LOCAL_STORAGE[key]["value"],
        "stored_at": LOCAL_STORAGE[key]["stored_at"],
    }


def tool_list_keys(params: dict) -> dict:
    """List all stored keys."""
    prefix = params.get("prefix", "")

    keys = [k for k in LOCAL_STORAGE.keys() if k.startswith(prefix)]

    return {"success": True, "count": len(keys), "keys": keys}


def tool_delete_value(params: dict) -> dict:
    """Delete a key from local memory."""
    key = params.get("key")

    if not key:
        return {"success": False, "error": "key parameter required"}

    if key not in LOCAL_STORAGE:
        return {"success": False, "error": f"Key not found: {key}"}

    del LOCAL_STORAGE[key]

    return {"success": True, "message": f"Key deleted: {key}"}


def tool_add_memory(params: dict) -> dict:
    """Add an entry to conversation memory."""
    content = params.get("content")
    role = params.get("role", "assistant")

    if not content:
        return {"success": False, "error": "content parameter required"}

    entry = {"role": role, "content": content, "timestamp": datetime.now().isoformat()}
    CONVERSATION_MEMORY.append(entry)

    return {"success": True, "memory_size": len(CONVERSATION_MEMORY), "entry": entry}


def tool_get_memory(params: dict) -> dict:
    """Retrieve conversation memory."""
    limit = params.get("limit", 10)

    entries = CONVERSATION_MEMORY[-limit:] if CONVERSATION_MEMORY else []

    return {
        "success": True,
        "total_entries": len(CONVERSATION_MEMORY),
        "returned_entries": len(entries),
        "memory": entries,
    }


def tool_clear_memory(params: dict) -> dict:
    """Clear conversation memory."""
    global CONVERSATION_MEMORY
    count = len(CONVERSATION_MEMORY)
    CONVERSATION_MEMORY = []

    return {"success": True, "cleared_entries": count}


def tool_get_env(params: dict) -> dict:
    """Get environment information (safe subset)."""
    return {
        "success": True,
        "environment": {
            "python_version": os.sys.version,
            "platform": os.sys.platform,
            "cwd": os.getcwd(),
            "server_mode": "local-development",
        },
    }


def tool_calculate(params: dict) -> dict:
    """Perform simple calculations."""
    expression = params.get("expression")

    if not expression:
        return {"success": False, "error": "expression parameter required"}

    # Safe evaluation of simple math expressions
    allowed_chars = set("0123456789+-*/.(). ")
    if not all(c in allowed_chars for c in expression):
        return {"success": False, "error": "Invalid characters in expression"}

    try:
        # Evaluate with restricted builtins
        result = eval(expression, {"__builtins__": {}}, {})
        return {"success": True, "expression": expression, "result": result}
    except Exception as e:
        return {"success": False, "error": f"Calculation error: {str(e)}"}


# Tool registry
TOOLS = {
    "echo": {
        "handler": tool_echo,
        "description": "Echo back input message",
        "parameters": {"message": "Message to echo back"},
    },
    "store_value": {
        "handler": tool_store_value,
        "description": "Store a key-value pair",
        "parameters": {"key": "Storage key (required)", "value": "Value to store"},
    },
    "get_value": {
        "handler": tool_get_value,
        "description": "Retrieve a stored value",
        "parameters": {"key": "Storage key (required)"},
    },
    "list_keys": {
        "handler": tool_list_keys,
        "description": "List all stored keys",
        "parameters": {"prefix": "Optional key prefix filter"},
    },
    "delete_value": {
        "handler": tool_delete_value,
        "description": "Delete a stored value",
        "parameters": {"key": "Storage key (required)"},
    },
    "add_memory": {
        "handler": tool_add_memory,
        "description": "Add entry to conversation memory",
        "parameters": {"content": "Memory content (required)", "role": "Role (user/assistant)"},
    },
    "get_memory": {
        "handler": tool_get_memory,
        "description": "Retrieve conversation memory",
        "parameters": {"limit": "Maximum entries to return"},
    },
    "clear_memory": {"handler": tool_clear_memory, "description": "Clear all conversation memory", "parameters": {}},
    "get_env": {"handler": tool_get_env, "description": "Get environment information", "parameters": {}},
    "calculate": {
        "handler": tool_calculate,
        "description": "Perform simple calculations",
        "parameters": {"expression": "Math expression (required)"},
    },
}


# =============================================================================
# MCP Protocol Endpoints
# =============================================================================


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy", "server": "local-dev-mcp", "timestamp": datetime.now().isoformat()})


@app.route("/tools/list", methods=["GET", "POST"])
def list_tools():
    """List available tools (MCP tools/list)."""
    tools_list = [
        {
            "name": name,
            "description": info["description"],
            "inputSchema": {
                "type": "object",
                "properties": {k: {"type": "string", "description": v} for k, v in info["parameters"].items()},
                "required": [k for k, v in info["parameters"].items() if "required" in v.lower()],
            },
        }
        for name, info in TOOLS.items()
    ]

    return jsonify(
        {"jsonrpc": "2.0", "result": {"tools": tools_list}, "id": request.json.get("id") if request.is_json else None}
    )


@app.route("/tools/call", methods=["POST"])
def call_tool():
    """Call a tool (MCP tools/call)."""
    if not request.is_json:
        return (
            jsonify({"jsonrpc": "2.0", "error": {"code": -32600, "message": "Request must be JSON"}, "id": None}),
            400,
        )

    data = request.json
    request_id = data.get("id")

    # Handle MCP protocol format
    if "params" in data:
        tool_name = data["params"].get("name")
        tool_args = data["params"].get("arguments", {})
    else:
        # Handle simple format
        tool_name = data.get("tool", data.get("name"))
        tool_args = data.get("arguments", data.get("parameters", {}))

    if not tool_name:
        return (
            jsonify({"jsonrpc": "2.0", "error": {"code": -32602, "message": "Tool name required"}, "id": request_id}),
            400,
        )

    if tool_name not in TOOLS:
        return (
            jsonify(
                {"jsonrpc": "2.0", "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"}, "id": request_id}
            ),
            404,
        )

    try:
        result = TOOLS[tool_name]["handler"](tool_args)
        return jsonify(
            {
                "jsonrpc": "2.0",
                "result": {"content": [{"type": "text", "text": json.dumps(result, default=json_serial)}]},
                "id": request_id,
            }
        )
    except Exception as e:
        logger.error(f"Tool execution error: {str(e)}")
        return jsonify({"jsonrpc": "2.0", "error": {"code": -32000, "message": str(e)}, "id": request_id}), 500


@app.route("/", methods=["POST"])
def mcp_endpoint():
    """Main MCP JSON-RPC endpoint."""
    if not request.is_json:
        return (
            jsonify({"jsonrpc": "2.0", "error": {"code": -32600, "message": "Request must be JSON"}, "id": None}),
            400,
        )

    data = request.json
    method = data.get("method", "")
    request_id = data.get("id")

    if method == "tools/list":
        return list_tools()
    elif method == "tools/call":
        return call_tool()
    else:
        return (
            jsonify(
                {"jsonrpc": "2.0", "error": {"code": -32601, "message": f"Unknown method: {method}"}, "id": request_id}
            ),
            404,
        )


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    debug = os.environ.get("DEBUG", "false").lower() == "true"

    print(
        f"""
╔══════════════════════════════════════════════════════════════╗
║           Local Development MCP Server                       ║
╠══════════════════════════════════════════════════════════════╣
║  Endpoints:                                                  ║
║    Health:     GET  http://localhost:{port}/health              ║
║    List Tools: GET  http://localhost:{port}/tools/list          ║
║    Call Tool:  POST http://localhost:{port}/tools/call          ║
║    MCP:        POST http://localhost:{port}/                    ║
╠══════════════════════════════════════════════════════════════╣
║  Available Tools:                                            ║
║    - echo          : Echo back messages                      ║
║    - store_value   : Store key-value pairs                   ║
║    - get_value     : Retrieve stored values                  ║
║    - list_keys     : List all keys                           ║
║    - delete_value  : Delete stored values                    ║
║    - add_memory    : Add to conversation memory              ║
║    - get_memory    : Retrieve conversation memory            ║
║    - clear_memory  : Clear all memory                        ║
║    - get_env       : Get environment info                    ║
║    - calculate     : Simple calculations                     ║
╚══════════════════════════════════════════════════════════════╝
    """
    )

    app.run(host="0.0.0.0", port=port, debug=debug)
