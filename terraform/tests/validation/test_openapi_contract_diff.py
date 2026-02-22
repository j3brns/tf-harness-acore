from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import sys
import unittest


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "openapi_contract_diff.py"
    spec = importlib.util.spec_from_file_location("openapi_contract_diff", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def _base_spec() -> dict:
    return {
        "openapi": "3.1.0",
        "info": {
            "title": "AgentCore MCP Tools API",
            "version": "1.0.0",
            "description": "Generated spec.",
        },
        "tags": [{"name": "local-dev", "description": "Tools from local-dev"}],
        "paths": {
            "/tools/local-dev/calculate": {
                "post": {
                    "tags": ["local-dev"],
                    "summary": "Calculate something",
                    "operationId": "local-dev_calculate",
                    "requestBody": {
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "expression": {
                                            "type": "string",
                                            "description": "Expression to evaluate",
                                        }
                                    },
                                    "required": ["expression"],
                                }
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "Successful execution",
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/ToolResponse"}
                                }
                            },
                        }
                    },
                }
            }
        },
        "components": {
            "schemas": {
                "ToolResponse": {
                    "type": "object",
                    "properties": {
                        "success": {"type": "boolean"},
                        "result": {"type": "object"},
                        "error": {"type": "string"},
                    },
                }
            }
        },
    }


class OpenApiContractDiffTests(unittest.TestCase):
    def test_doc_only_description_and_summary_changes(self):
        old = _base_spec()
        new = copy.deepcopy(old)
        new["info"]["description"] = "Generated spec (updated wording)."
        op = new["paths"]["/tools/local-dev/calculate"]["post"]
        op["summary"] = "Calculate a value"
        op["requestBody"]["content"]["application/json"]["schema"]["properties"]["expression"][
            "description"
        ] = "Math expression to evaluate"

        diff = mod.diff_specs(old, new)

        self.assertEqual(diff["counts"]["breaking"], 0)
        self.assertEqual(diff["counts"]["additive"], 0)
        self.assertGreaterEqual(diff["counts"]["doc_only"], 3)

    def test_additive_optional_property_and_operation(self):
        old = _base_spec()
        new = copy.deepcopy(old)
        schema = (
            new["paths"]["/tools/local-dev/calculate"]["post"]["requestBody"]["content"]["application/json"]["schema"]
        )
        schema["properties"]["precision"] = {"type": "string", "description": "Optional precision"}
        new["paths"]["/tools/local-dev/health"] = {
            "post": {
                "tags": ["local-dev"],
                "summary": "Health check",
                "operationId": "local-dev_health",
                "responses": {"200": {"description": "ok"}},
            }
        }

        diff = mod.diff_specs(old, new)
        additive_codes = {item["code"] for item in diff["changes"]["additive"]}

        self.assertEqual(diff["counts"]["breaking"], 0)
        self.assertIn("request_property_added_optional", additive_codes)
        self.assertTrue({"path_added", "operation_added"} & additive_codes)

    def test_breaking_required_property_and_type_change(self):
        old = _base_spec()
        new = copy.deepcopy(old)
        schema = (
            new["paths"]["/tools/local-dev/calculate"]["post"]["requestBody"]["content"]["application/json"]["schema"]
        )
        schema["properties"]["mode"] = {"type": "string", "description": "Mode"}
        schema["required"] = ["expression", "mode"]
        schema["properties"]["expression"]["type"] = "number"

        diff = mod.diff_specs(old, new)
        breaking_codes = {item["code"] for item in diff["changes"]["breaking"]}

        self.assertGreaterEqual(diff["counts"]["breaking"], 2)
        self.assertIn("request_property_added_required", breaking_codes)
        self.assertIn("property_type_changed", breaking_codes)

    def test_markdown_summary_includes_counts_and_sections(self):
        old = _base_spec()
        new = copy.deepcopy(old)
        new["info"]["description"] = "Changed"
        diff = mod.diff_specs(old, new)

        summary = mod.render_markdown(diff, "base.json", "head.json")

        self.assertIn("## OpenAPI Contract Diff Summary", summary)
        self.assertIn("Baseline: `base.json`", summary)
        self.assertIn("Candidate: `head.json`", summary)
        self.assertIn("Documentation-Only Changes", summary)


if __name__ == "__main__":
    unittest.main()
