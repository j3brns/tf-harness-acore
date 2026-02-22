#!/usr/bin/env python3
"""Generate a classified OpenAPI contract diff/changelog summary.

Compares two OpenAPI JSON documents and classifies changes into:
- breaking (potentially breaking consumer impact)
- additive (generally non-breaking contract additions/relaxations)
- doc_only (descriptions/summaries/tag metadata)

Designed for the repo's generated MCP tools OpenAPI contract, but implemented with
generic OpenAPI object/schema comparisons and stdlib-only dependencies.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


DOC_FIELDS = {
    "description",
    "summary",
    "title",
    "example",
    "examples",
    "externalDocs",
}


@dataclass(frozen=True)
class Change:
    code: str
    target: str
    detail: str


def load_json(path: str) -> dict[str, Any]:
    file_path = Path(path)
    with file_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object at {path}")
    return data


def add_change(changes: dict[str, list[Change]], category: str, code: str, target: str, detail: str) -> None:
    changes[category].append(Change(code=code, target=target, detail=detail))


def sorted_methods(path_item: dict[str, Any]) -> list[str]:
    return sorted(k for k, v in path_item.items() if isinstance(v, dict))


def operation_ref(path: str, method: str) -> str:
    return f"{method.upper()} {path}"


def get_request_schema(operation: dict[str, Any]) -> dict[str, Any] | None:
    request_body = operation.get("requestBody")
    if not isinstance(request_body, dict):
        return None
    content = request_body.get("content")
    if not isinstance(content, dict):
        return None
    app_json = content.get("application/json")
    if not isinstance(app_json, dict):
        return None
    schema = app_json.get("schema")
    return schema if isinstance(schema, dict) else None


def get_response_map(operation: dict[str, Any]) -> dict[str, dict[str, Any]]:
    responses = operation.get("responses")
    if not isinstance(responses, dict):
        return {}
    return {str(code): value for code, value in responses.items() if isinstance(value, dict)}


def get_response_schema(response: dict[str, Any]) -> dict[str, Any] | None:
    content = response.get("content")
    if not isinstance(content, dict):
        return None
    app_json = content.get("application/json")
    if not isinstance(app_json, dict):
        return None
    schema = app_json.get("schema")
    return schema if isinstance(schema, dict) else None


def strip_doc_fields(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: strip_doc_fields(v) for k, v in sorted(value.items()) if k not in DOC_FIELDS}
    if isinstance(value, list):
        return [strip_doc_fields(v) for v in value]
    return value


def contract_signature(value: Any) -> str:
    return json.dumps(strip_doc_fields(value), sort_keys=True, separators=(",", ":"))


def schema_type_name(schema: dict[str, Any]) -> str:
    if "$ref" in schema and isinstance(schema["$ref"], str):
        return f"$ref:{schema['$ref']}"
    schema_type = schema.get("type")
    if isinstance(schema_type, list):
        return "|".join(str(x) for x in schema_type)
    if isinstance(schema_type, str):
        return schema_type
    return "unspecified"


def schema_properties(schema: dict[str, Any]) -> dict[str, dict[str, Any]]:
    properties = schema.get("properties")
    if not isinstance(properties, dict):
        return {}
    return {str(name): value for name, value in properties.items() if isinstance(value, dict)}


def schema_required(schema: dict[str, Any]) -> set[str]:
    required = schema.get("required")
    if not isinstance(required, list):
        return set()
    return {str(item) for item in required}


def compare_scalar_doc_field(
    changes: dict[str, list[Change]],
    target: str,
    field: str,
    old_value: Any,
    new_value: Any,
) -> None:
    if old_value != new_value:
        add_change(
            changes,
            "doc_only",
            "metadata_changed",
            target,
            f"{field} changed from {old_value!r} to {new_value!r}",
        )


def compare_info(old_spec: dict[str, Any], new_spec: dict[str, Any], changes: dict[str, list[Change]]) -> None:
    old_info = old_spec.get("info") if isinstance(old_spec.get("info"), dict) else {}
    new_info = new_spec.get("info") if isinstance(new_spec.get("info"), dict) else {}
    for field in ("title", "version", "description"):
        compare_scalar_doc_field(changes, "info", field, old_info.get(field), new_info.get(field))


def compare_tags(old_spec: dict[str, Any], new_spec: dict[str, Any], changes: dict[str, list[Change]]) -> None:
    def index_tags(spec: dict[str, Any]) -> dict[str, dict[str, Any]]:
        tags = spec.get("tags")
        if not isinstance(tags, list):
            return {}
        out: dict[str, dict[str, Any]] = {}
        for item in tags:
            if not isinstance(item, dict):
                continue
            name = item.get("name")
            if isinstance(name, str):
                out[name] = item
        return out

    old_tags = index_tags(old_spec)
    new_tags = index_tags(new_spec)
    for removed in sorted(set(old_tags) - set(new_tags)):
        add_change(changes, "doc_only", "tag_removed", f"tag:{removed}", "Top-level tag metadata removed")
    for added in sorted(set(new_tags) - set(old_tags)):
        add_change(changes, "doc_only", "tag_added", f"tag:{added}", "Top-level tag metadata added")
    for name in sorted(set(old_tags) & set(new_tags)):
        compare_scalar_doc_field(
            changes,
            f"tag:{name}",
            "description",
            old_tags[name].get("description"),
            new_tags[name].get("description"),
        )


def compare_object_schema(
    old_schema: dict[str, Any],
    new_schema: dict[str, Any],
    target: str,
    changes: dict[str, list[Change]],
) -> None:
    old_type = schema_type_name(old_schema)
    new_type = schema_type_name(new_schema)
    if old_type != new_type:
        add_change(
            changes,
            "breaking",
            "schema_type_changed",
            target,
            f"Schema type changed from {old_type} to {new_type}",
        )
        return

    # For non-object schemas, compare contract signature and doc fields only.
    if old_type != "object":
        if contract_signature(old_schema) != contract_signature(new_schema):
            add_change(changes, "breaking", "schema_changed", target, "Schema contract changed")
        for field in ("description", "title"):
            compare_scalar_doc_field(changes, target, field, old_schema.get(field), new_schema.get(field))
        return

    old_props = schema_properties(old_schema)
    new_props = schema_properties(new_schema)
    old_required = schema_required(old_schema)
    new_required = schema_required(new_schema)

    removed_props = sorted(set(old_props) - set(new_props))
    added_props = sorted(set(new_props) - set(old_props))
    common_props = sorted(set(old_props) & set(new_props))

    for prop_name in removed_props:
        add_change(
            changes,
            "breaking",
            "request_property_removed" if target.startswith("request:") else "schema_property_removed",
            f"{target}.{prop_name}",
            "Property removed",
        )

    for prop_name in added_props:
        is_required = prop_name in new_required
        category = "breaking" if is_required else "additive"
        code = (
            "request_property_added_required"
            if target.startswith("request:") and is_required
            else "request_property_added_optional"
            if target.startswith("request:")
            else "schema_property_added_required"
            if is_required
            else "schema_property_added_optional"
        )
        detail = "Required property added" if is_required else "Optional property added"
        add_change(changes, category, code, f"{target}.{prop_name}", detail)

    for prop_name in common_props:
        old_prop = old_props[prop_name]
        new_prop = new_props[prop_name]
        old_prop_type = schema_type_name(old_prop)
        new_prop_type = schema_type_name(new_prop)
        prop_target = f"{target}.{prop_name}"
        if old_prop_type != new_prop_type:
            add_change(
                changes,
                "breaking",
                "property_type_changed",
                prop_target,
                f"Type changed from {old_prop_type} to {new_prop_type}",
            )
        elif contract_signature(old_prop) != contract_signature(new_prop):
            add_change(
                changes,
                "breaking",
                "property_contract_changed",
                prop_target,
                "Property schema contract changed",
            )
        for field in ("description", "title"):
            compare_scalar_doc_field(changes, prop_target, field, old_prop.get(field), new_prop.get(field))

        old_required_here = prop_name in old_required
        new_required_here = prop_name in new_required
        if old_required_here != new_required_here:
            if new_required_here:
                add_change(
                    changes,
                    "breaking",
                    "property_became_required",
                    prop_target,
                    "Existing optional property became required",
                )
            else:
                add_change(
                    changes,
                    "additive",
                    "property_no_longer_required",
                    prop_target,
                    "Existing required property is now optional",
                )

    for field in ("description", "title"):
        compare_scalar_doc_field(changes, target, field, old_schema.get(field), new_schema.get(field))


def compare_operation(
    path: str,
    method: str,
    old_op: dict[str, Any],
    new_op: dict[str, Any],
    changes: dict[str, list[Change]],
) -> None:
    target = operation_ref(path, method)
    for field in ("summary", "description"):
        compare_scalar_doc_field(changes, target, field, old_op.get(field), new_op.get(field))

    old_tags = old_op.get("tags") if isinstance(old_op.get("tags"), list) else []
    new_tags = new_op.get("tags") if isinstance(new_op.get("tags"), list) else []
    if old_tags != new_tags:
        add_change(changes, "doc_only", "operation_tags_changed", target, "Operation tags changed")

    if old_op.get("operationId") != new_op.get("operationId"):
        add_change(
            changes,
            "breaking",
            "operation_id_changed",
            target,
            f"operationId changed from {old_op.get('operationId')!r} to {new_op.get('operationId')!r}",
        )

    old_request = get_request_schema(old_op)
    new_request = get_request_schema(new_op)
    request_target = f"request:{target}"
    if old_request and not new_request:
        add_change(changes, "additive", "request_body_removed", request_target, "application/json request body removed")
    elif not old_request and new_request:
        add_change(changes, "breaking", "request_body_added", request_target, "application/json request body added")
    elif old_request and new_request:
        compare_object_schema(old_request, new_request, request_target, changes)

    old_responses = get_response_map(old_op)
    new_responses = get_response_map(new_op)
    for code in sorted(set(old_responses) - set(new_responses)):
        add_change(changes, "breaking", "response_removed", f"{target} -> {code}", "Response removed")
    for code in sorted(set(new_responses) - set(old_responses)):
        add_change(changes, "additive", "response_added", f"{target} -> {code}", "Response added")
    for code in sorted(set(old_responses) & set(new_responses)):
        resp_target = f"{target} -> {code}"
        compare_scalar_doc_field(
            changes,
            resp_target,
            "description",
            old_responses[code].get("description"),
            new_responses[code].get("description"),
        )
        old_schema = get_response_schema(old_responses[code])
        new_schema = get_response_schema(new_responses[code])
        if bool(old_schema) != bool(new_schema):
            category = "breaking" if new_schema else "additive"
            code_name = "response_schema_added" if new_schema and not old_schema else "response_schema_removed"
            detail = "Response schema added" if new_schema and not old_schema else "Response schema removed"
            add_change(changes, category, code_name, resp_target, detail)
        elif old_schema and new_schema and contract_signature(old_schema) != contract_signature(new_schema):
            add_change(changes, "breaking", "response_schema_changed", resp_target, "Response schema contract changed")


def compare_paths(old_spec: dict[str, Any], new_spec: dict[str, Any], changes: dict[str, list[Change]]) -> None:
    old_paths = old_spec.get("paths") if isinstance(old_spec.get("paths"), dict) else {}
    new_paths = new_spec.get("paths") if isinstance(new_spec.get("paths"), dict) else {}

    for path in sorted(set(old_paths) - set(new_paths)):
        add_change(changes, "breaking", "path_removed", path, "Path removed")
    for path in sorted(set(new_paths) - set(old_paths)):
        add_change(changes, "additive", "path_added", path, "Path added")

    for path in sorted(set(old_paths) & set(new_paths)):
        old_item = old_paths[path] if isinstance(old_paths[path], dict) else {}
        new_item = new_paths[path] if isinstance(new_paths[path], dict) else {}

        old_methods = set(sorted_methods(old_item))
        new_methods = set(sorted_methods(new_item))

        for method in sorted(old_methods - new_methods):
            add_change(changes, "breaking", "operation_removed", operation_ref(path, method), "Operation removed")
        for method in sorted(new_methods - old_methods):
            add_change(changes, "additive", "operation_added", operation_ref(path, method), "Operation added")
        for method in sorted(old_methods & new_methods):
            compare_operation(path, method, old_item[method], new_item[method], changes)


def compare_components(old_spec: dict[str, Any], new_spec: dict[str, Any], changes: dict[str, list[Change]]) -> None:
    old_components = old_spec.get("components") if isinstance(old_spec.get("components"), dict) else {}
    new_components = new_spec.get("components") if isinstance(new_spec.get("components"), dict) else {}
    old_schemas = old_components.get("schemas") if isinstance(old_components.get("schemas"), dict) else {}
    new_schemas = new_components.get("schemas") if isinstance(new_components.get("schemas"), dict) else {}

    for name in sorted(set(old_schemas) - set(new_schemas)):
        add_change(changes, "breaking", "component_schema_removed", f"#/components/schemas/{name}", "Schema removed")
    for name in sorted(set(new_schemas) - set(old_schemas)):
        add_change(changes, "additive", "component_schema_added", f"#/components/schemas/{name}", "Schema added")
    for name in sorted(set(old_schemas) & set(new_schemas)):
        old_schema = old_schemas[name]
        new_schema = new_schemas[name]
        if not isinstance(old_schema, dict) or not isinstance(new_schema, dict):
            if contract_signature(old_schema) != contract_signature(new_schema):
                add_change(
                    changes,
                    "breaking",
                    "component_schema_changed",
                    f"#/components/schemas/{name}",
                    "Component schema changed",
                )
            continue
        compare_object_schema(old_schema, new_schema, f"#/components/schemas/{name}", changes)


def diff_specs(old_spec: dict[str, Any], new_spec: dict[str, Any]) -> dict[str, Any]:
    changes: dict[str, list[Change]] = {"breaking": [], "additive": [], "doc_only": []}
    compare_info(old_spec, new_spec, changes)
    compare_tags(old_spec, new_spec, changes)
    compare_paths(old_spec, new_spec, changes)
    compare_components(old_spec, new_spec, changes)

    for key in changes:
        changes[key] = sorted(changes[key], key=lambda c: (c.target, c.code, c.detail))

    result = {
        "counts": {key: len(changes[key]) for key in ("breaking", "additive", "doc_only")},
        "changes": {key: [asdict(item) for item in changes[key]] for key in ("breaking", "additive", "doc_only")},
    }
    result["has_changes"] = any(result["counts"].values())
    return result


def render_markdown(diff_result: dict[str, Any], old_label: str, new_label: str, max_items: int = 200) -> str:
    counts = diff_result["counts"]
    lines = [
        "## OpenAPI Contract Diff Summary",
        "",
        f"- Baseline: `{old_label}`",
        f"- Candidate: `{new_label}`",
        "",
        f"- Potentially breaking changes: **{counts['breaking']}**",
        f"- Additive / relaxed changes: **{counts['additive']}**",
        f"- Documentation-only changes: **{counts['doc_only']}**",
        "",
    ]

    if not diff_result.get("has_changes"):
        lines.append("No OpenAPI contract changes detected.")
        return "\n".join(lines) + "\n"

    sections = [
        ("breaking", "Potentially Breaking Changes"),
        ("additive", "Additive / Relaxed Changes"),
        ("doc_only", "Documentation-Only Changes"),
    ]
    for key, title in sections:
        items = diff_result["changes"][key]
        lines.extend([f"### {title}", ""])
        if not items:
            lines.append("- None")
            lines.append("")
            continue
        for item in items[:max_items]:
            lines.append(f"- `{item['code']}` `{item['target']}`: {item['detail']}")
        if len(items) > max_items:
            lines.append(f"- ... {len(items) - max_items} additional changes omitted")
        lines.append("")

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a classified OpenAPI contract diff summary")
    parser.add_argument("--old", required=True, help="Path to baseline OpenAPI JSON")
    parser.add_argument("--new", required=True, help="Path to candidate OpenAPI JSON")
    parser.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument("--old-label", help="Display label for --old (defaults to path)")
    parser.add_argument("--new-label", help="Display label for --new (defaults to path)")
    parser.add_argument(
        "--fail-on-breaking",
        action="store_true",
        help="Return exit code 2 if potentially breaking changes are detected",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        old_spec = load_json(args.old)
        new_spec = load_json(args.new)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    diff_result = diff_specs(old_spec, new_spec)

    if args.format == "json":
        print(json.dumps(diff_result, indent=2, sort_keys=True))
    else:
        print(
            render_markdown(
                diff_result,
                old_label=args.old_label or args.old,
                new_label=args.new_label or args.new,
            ),
            end="",
        )

    if args.fail_on_breaking and diff_result["counts"]["breaking"] > 0:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
