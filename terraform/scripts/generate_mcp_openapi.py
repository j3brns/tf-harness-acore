import os
import ast
import json
import glob
from typing import Dict, Any, List

def parse_tools_from_file(file_path: str) -> Dict[str, Any]:
    """
    Parses the TOOLS dictionary from a Python file using AST.
    Safely extracts description and parameters, ignoring function references.
    """
    with open(file_path, 'r') as f:
        tree = ast.parse(f.read())
    
    tools = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == 'TOOLS':
                    if isinstance(node.value, ast.Dict):
                        for key, value in zip(node.value.keys, node.value.values):
                            if isinstance(key, ast.Constant):
                                tool_name = key.value
                                tool_info = {}
                                if isinstance(value, ast.Dict):
                                    for t_key, t_value in zip(value.keys, value.values):
                                        if isinstance(t_key, ast.Constant):
                                            if t_key.value in ['description', 'parameters']:
                                                # Use ast.literal_eval for these safe values
                                                tool_info[t_key.value] = ast.literal_eval(t_value)
                                tools[tool_name] = tool_info
    return tools

def build_openapi_spec(all_tools: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    """
    Builds an OpenAPI 3.1.0 specification from the collected tools.
    """
    spec = {
        "openapi": "3.1.0",
        "info": {
            "title": "AgentCore MCP Tools API",
            "version": "1.0.0",
            "description": "Automatically generated OpenAPI spec from MCP tools registry.",
        },
        "paths": {},
        "components": {
            "schemas": {
                "ToolResponse": {
                    "type": "object",
                    "properties": {
                        "success": {"type": "boolean"},
                        "result": {"type": "object"},
                        "error": {"type": "string"}
                    }
                }
            }
        },
        "tags": []
    }

    for server_name, tools in all_tools.items():
        spec["tags"].append({
            "name": server_name,
            "description": f"Tools from {server_name} MCP server"
        })
        
        for tool_name, info in tools.items():
            path = f"/tools/{server_name}/{tool_name}"
            description = info.get('description', '')
            parameters = info.get('parameters', {})
            
            properties = {}
            required = []
            for param_name, param_desc in parameters.items():
                properties[param_name] = {
                    "type": "string",
                    "description": param_desc
                }
                if 'required' in param_desc.lower():
                    required.append(param_name)
            
            operation = {
                "tags": [server_name],
                "summary": description,
                "operationId": f"{server_name}_{tool_name}",
                "requestBody": {
                    "content": {
                        "application/json": {
                            "schema": {
                                "type": "object",
                                "properties": properties,
                            }
                        }
                    }
                },
                "responses": {
                    "200": {
                        "description": "Successful tool execution",
                        "content": {
                            "application/json": {
                                "schema": {
                                    "$ref": "#/components/schemas/ToolResponse"
                                }
                            }
                        }
                    }
                }
            }
            
            if required:
                operation["requestBody"]["content"]["application/json"]["schema"]["required"] = required
            
            spec["paths"][path] = {"post": operation}

    return spec

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
    mcp_servers_dir = os.path.join(repo_root, 'examples/mcp-servers')
    output_path = os.path.join(repo_root, 'docs/api/mcp-tools-v1.openapi.json')
    
    all_tools = {}
    
    # Find all handler.py and server.py files
    search_patterns = [
        os.path.join(mcp_servers_dir, '*/handler.py'),
        os.path.join(mcp_servers_dir, '*/server.py')
    ]
    
    files = []
    for pattern in search_patterns:
        files.extend(glob.glob(pattern))
    
    for file_path in files:
        server_name = os.path.basename(os.path.dirname(file_path))
        if server_name in ['scripts', 'terraform']:
            continue
            
        print(f"Processing {server_name} from {file_path}...")
        tools = parse_tools_from_file(file_path)
        if tools:
            all_tools[server_name] = tools
            print(f"  Found {len(tools)} tools.")
        else:
            print(f"  No TOOLS dictionary found.")
            
    if not all_tools:
        print("No tools found. Check the search patterns and file contents.")
        return
        
    spec = build_openapi_spec(all_tools)
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        json.dump(spec, f, indent=2)
        
    print(f"Successfully generated OpenAPI spec at {output_path}")

if __name__ == "__main__":
    main()
