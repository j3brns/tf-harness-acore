#!/usr/bin/env python3
"""Generate a typed TypeScript client from the MCP tools OpenAPI spec."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any


DEFAULT_INPUT = "docs/api/mcp-tools-v1.openapi.json"
DEFAULT_OUTPUT = "docs/api/mcp-tools-v1.client.ts"


def _read_json(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _sanitize_words(value: str) -> list[str]:
    words = re.findall(r"[A-Za-z0-9]+", value)
    return [word for word in words if word]


def _to_pascal_case(value: str) -> str:
    words = _sanitize_words(value)
    if not words:
        return "GeneratedName"
    parts = [word[:1].upper() + word[1:] for word in words]
    candidate = "".join(parts)
    if candidate[0].isdigit():
        return f"N{candidate}"
    return candidate


def _to_camel_case(value: str) -> str:
    pascal = _to_pascal_case(value)
    return pascal[:1].lower() + pascal[1:]


def _escape_ts_string(value: str) -> str:
    return json.dumps(value)


def _indent(text: str, spaces: int = 2) -> str:
    pad = " " * spaces
    return "\n".join(f"{pad}{line}" if line else "" for line in text.splitlines())


def _schema_to_ts_type(schema: dict[str, Any] | None, components: dict[str, Any]) -> str:
    if not schema:
        return "Record<string, unknown>"

    ref = schema.get("$ref")
    if isinstance(ref, str) and ref.startswith("#/components/schemas/"):
        return _to_pascal_case(ref.split("/")[-1])

    schema_type = schema.get("type")

    if schema_type == "string":
        return "string"
    if schema_type == "integer":
        return "number"
    if schema_type == "number":
        return "number"
    if schema_type == "boolean":
        return "boolean"
    if schema_type == "array":
        return f"{_schema_to_ts_type(schema.get('items', {}), components)}[]"
    if schema_type == "object":
        properties = schema.get("properties")
        if not isinstance(properties, dict) or not properties:
            return "Record<string, unknown>"
        required = set(schema.get("required", []))
        fields: list[str] = ["{"]
        for prop_name in sorted(properties):
            prop_schema = properties[prop_name]
            optional = "" if prop_name in required else "?"
            ts_type = _schema_to_ts_type(prop_schema, components)
            fields.append(f"  {prop_name}{optional}: {ts_type};")
        fields.append("}")
        return "\n".join(fields)

    if "enum" in schema and isinstance(schema["enum"], list):
        enum_values = schema["enum"]
        if all(isinstance(v, str) for v in enum_values):
            return " | ".join(_escape_ts_string(v) for v in enum_values) or "string"

    # Best effort for schemas without explicit type (common in generated/partial specs).
    if "properties" in schema or "additionalProperties" in schema:
        return "Record<string, unknown>"

    return "unknown"


def _build_request_interface(name: str, schema: dict[str, Any] | None, components: dict[str, Any]) -> str:
    if not schema:
        return f"export type {name} = Record<string, never>;"

    properties = schema.get("properties", {})
    if not isinstance(properties, dict) or not properties:
        return f"export type {name} = Record<string, never>;"

    required = set(schema.get("required", []))
    lines = [f"export interface {name} {{"]
    for prop_name in sorted(properties):
        prop_schema = properties[prop_name]
        optional = "" if prop_name in required else "?"
        ts_type = _schema_to_ts_type(prop_schema, components)
        description = prop_schema.get("description")
        if isinstance(description, str) and description.strip():
            lines.append(f"  /** {description.strip()} */")
        lines.append(f"  {prop_name}{optional}: {ts_type};")
    lines.append("}")
    return "\n".join(lines)


def _build_component_interfaces(spec: dict[str, Any]) -> list[str]:
    components = spec.get("components", {})
    schemas = components.get("schemas", {})
    if not isinstance(schemas, dict):
        return []

    blocks: list[str] = []
    for schema_name in sorted(schemas):
        schema = schemas[schema_name]
        if not isinstance(schema, dict):
            continue
        type_name = _to_pascal_case(schema_name)
        schema_type = schema.get("type")
        if schema_type == "object":
            properties = schema.get("properties", {})
            required = set(schema.get("required", []))
            lines = [f"export interface {type_name} {{"]
            if isinstance(properties, dict):
                for prop_name in sorted(properties):
                    prop_schema = properties[prop_name]
                    optional = "" if prop_name in required else "?"
                    ts_type = _schema_to_ts_type(prop_schema, components)
                    lines.append(f"  {prop_name}{optional}: {ts_type};")
            lines.append("}")
            blocks.append("\n".join(lines))
        else:
            ts_type = _schema_to_ts_type(schema, components)
            blocks.append(f"export type {type_name} = {ts_type};")
    return blocks


def _extract_operations(spec: dict[str, Any]) -> list[dict[str, Any]]:
    paths = spec.get("paths", {})
    components = spec.get("components", {})
    if not isinstance(paths, dict):
        return []

    operations: list[dict[str, Any]] = []
    for path in sorted(paths):
        item = paths[path]
        if not isinstance(item, dict):
            continue
        post_op = item.get("post")
        if not isinstance(post_op, dict):
            continue

        operation_id = post_op.get("operationId")
        if not isinstance(operation_id, str) or not operation_id:
            continue

        request_schema = post_op.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema")
        if not isinstance(request_schema, dict):
            request_schema = {}

        response_schema = (
            post_op.get("responses", {}).get("200", {}).get("content", {}).get("application/json", {}).get("schema", {})
        )
        if not isinstance(response_schema, dict):
            response_schema = {}

        request_type_name = f"{_to_pascal_case(operation_id)}Request"
        method_name = _to_camel_case(operation_id)
        response_type = _schema_to_ts_type(response_schema, components)

        operations.append(
            {
                "path": path,
                "operation_id": operation_id,
                "summary": post_op.get("summary", ""),
                "request_schema": request_schema,
                "request_type_name": request_type_name,
                "response_type": response_type,
                "method_name": method_name,
            }
        )

    return operations


def build_client_source(spec: dict[str, Any], source_rel_path: str) -> str:
    components = spec.get("components", {})
    operations = _extract_operations(spec)

    lines: list[str] = [
        "/* eslint-disable */",
        f"// Generated by terraform/scripts/generate_mcp_typescript_client.py from {source_rel_path}.",
        "// Do not edit manually. Regenerate with: make generate-openapi-client",
        "",
        "export type JsonObject = Record<string, unknown>;",
        "",
    ]

    component_blocks = _build_component_interfaces(spec)
    if component_blocks:
        for block in component_blocks:
            lines.extend([block, ""])

    request_blocks = [
        _build_request_interface(op["request_type_name"], op["request_schema"], components) for op in operations
    ]
    for block in request_blocks:
        lines.extend([block, ""])

    lines.extend(
        [
            "export interface McpToolRequestOptions extends Omit<RequestInit, 'method' | 'body'> {",
            "  headers?: HeadersInit;",
            "}",
            "",
            "export interface McpToolsClientOptions {",
            "  baseUrl?: string;",
            "  fetchFn?: typeof fetch;",
            "  defaultHeaders?: HeadersInit;",
            "}",
            "",
            "export const MCP_TOOL_OPERATIONS = {",
        ]
    )

    for op in operations:
        lines.append(f"  {op['operation_id']!r}: {{ path: {_escape_ts_string(op['path'])}, method: 'POST' as const }},")
    lines.extend(["} as const;", "", "export type McpToolOperationId = keyof typeof MCP_TOOL_OPERATIONS;", ""])

    lines.append("export interface McpToolRequestMap {")
    for op in operations:
        lines.append(f"  {_escape_ts_string(op['operation_id'])}: {op['request_type_name']};")
    lines.extend(["}", "", "export interface McpToolResponseMap {"])
    for op in operations:
        lines.append(f"  {_escape_ts_string(op['operation_id'])}: {op['response_type']};")
    lines.extend(["}", ""])

    lines.extend(
        [
            "export class McpToolsClient {",
            "  private readonly baseUrl: string;",
            "  private readonly fetchFn: typeof fetch;",
            "  private readonly defaultHeaders?: HeadersInit;",
            "",
            "  constructor(options: McpToolsClientOptions = {}) {",
            "    this.baseUrl = (options.baseUrl ?? '').replace(/\\/$/, '');",
            "    const resolvedFetch = options.fetchFn ?? globalThis.fetch;",
            "    if (typeof resolvedFetch !== 'function') {",
            "      throw new Error('No fetch implementation available. Provide options.fetchFn.');",
            "    }",
            "    this.fetchFn = resolvedFetch.bind(globalThis) as typeof fetch;",
            "    this.defaultHeaders = options.defaultHeaders;",
            "  }",
            "",
            "  async invoke<T extends McpToolOperationId>(",
            "    operationId: T,",
            "    payload: McpToolRequestMap[T],",
            "    options: McpToolRequestOptions = {}",
            "  ): Promise<McpToolResponseMap[T]> {",
            "    const meta = MCP_TOOL_OPERATIONS[operationId];",
            "    return this.post(meta.path, payload, options) as Promise<McpToolResponseMap[T]>;",
            "  }",
            "",
            "  private async post(path: string, payload: unknown, options: McpToolRequestOptions): Promise<unknown> {",
            "    const headers = new Headers(this.defaultHeaders ?? {});",
            "    headers.set('Content-Type', 'application/json');",
            "    if (options.headers) {",
            "      new Headers(options.headers).forEach((value, key) => headers.set(key, value));",
            "    }",
            "",
            "    const response = await this.fetchFn(`${this.baseUrl}${path}`, {",
            "      ...options,",
            "      method: 'POST',",
            "      headers,",
            "      body: JSON.stringify(payload ?? {}),",
            "    });",
            "",
            "    if (!response.ok) {",
            "      const text = await response.text();",
            "      throw new Error(`MCP tool request failed (${response.status} ${response.statusText}): ${text}`);",
            "    }",
            "",
            "    return response.json();",
            "  }",
            "",
        ]
    )

    for op in operations:
        summary = str(op.get("summary") or "").strip()
        if summary:
            lines.append(f"  /** {summary} */")
        lines.extend(
            [
                f"  async {op['method_name']}(",
                f"    payload: {op['request_type_name']},",
                "    options: McpToolRequestOptions = {}",
                f"  ): Promise<{op['response_type']}> {{",
                f"    return this.invoke({_escape_ts_string(op['operation_id'])}, payload, options);",
                "  }",
                "",
            ]
        )

    lines.extend(["}", ""])
    return "\n".join(lines)


def _resolve_repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _compare_or_write(output_path: str, content: str, check: bool) -> int:
    if check:
        try:
            with open(output_path, "r", encoding="utf-8") as f:
                existing = f.read()
        except FileNotFoundError:
            print(f"ERROR: Generated client file is missing: {output_path}")
            return 1
        if existing != content:
            print(f"ERROR: Generated TypeScript client is out of date: {output_path}")
            print("Run: make generate-openapi-client")
            return 1
        print(f"Generated TypeScript client is up to date: {output_path}")
        return 0

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    print(f"Successfully generated TypeScript client at {output_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=DEFAULT_INPUT, help="OpenAPI spec path (repo-relative or absolute)")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Generated TypeScript client path")
    parser.add_argument("--check", action="store_true", help="Verify output matches generated content without writing")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = _resolve_repo_root()

    input_path = args.input if os.path.isabs(args.input) else os.path.join(repo_root, args.input)
    output_path = args.output if os.path.isabs(args.output) else os.path.join(repo_root, args.output)

    spec = _read_json(input_path)
    source_rel = os.path.relpath(input_path, repo_root)
    content = build_client_source(spec, source_rel)
    return _compare_or_write(output_path, content, args.check)


if __name__ == "__main__":
    sys.exit(main())
