import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SPEC_PATH = ROOT / "docs" / "api" / "tenancy-admin-v1.openapi.json"
FIXTURES_DIR = ROOT / "terraform" / "tests" / "fixtures" / "tenancy_admin_api_v1"


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _spec():
    return _load_json(SPEC_PATH)


def _resolve_ref(spec, ref):
    if not ref.startswith("#/"):
        raise AssertionError(f"Unsupported ref format: {ref}")
    node = spec
    for part in ref.lstrip("#/").split("/"):
        node = node[part]
    return node


def _assert_matches_schema(spec, schema, value, path="$"):
    if "$ref" in schema:
        return _assert_matches_schema(spec, _resolve_ref(spec, schema["$ref"]), value, path)

    if "enum" in schema:
        assert value in schema["enum"], f"{path}: {value!r} not in enum {schema['enum']}"

    schema_type = schema.get("type")
    if schema_type == "object":
        assert isinstance(value, dict), f"{path}: expected object"
        required = schema.get("required", [])
        for key in required:
            assert key in value, f"{path}: missing required key {key!r}"

        props = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        for key, item in value.items():
            if key in props:
                _assert_matches_schema(spec, props[key], item, f"{path}.{key}")
                continue
            if additional is False:
                raise AssertionError(f"{path}: unexpected key {key!r}")
            if isinstance(additional, dict):
                _assert_matches_schema(spec, additional, item, f"{path}.{key}")
        return

    if schema_type == "array":
        assert isinstance(value, list), f"{path}: expected array"
        if "maxItems" in schema:
            assert len(value) <= schema["maxItems"], f"{path}: too many items"
        if "minItems" in schema:
            assert len(value) >= schema["minItems"], f"{path}: too few items"
        item_schema = schema.get("items", {})
        for idx, item in enumerate(value):
            _assert_matches_schema(spec, item_schema, item, f"{path}[{idx}]")
        return

    if schema_type == "string":
        assert isinstance(value, str), f"{path}: expected string"
        if "minLength" in schema:
            assert len(value) >= schema["minLength"], f"{path}: shorter than minLength"
        if "maxLength" in schema:
            assert len(value) <= schema["maxLength"], f"{path}: longer than maxLength"
        return

    if schema_type == "integer":
        assert isinstance(value, int) and not isinstance(value, bool), f"{path}: expected integer"
        if "minimum" in schema:
            assert value >= schema["minimum"], f"{path}: below minimum"
        if "maximum" in schema:
            assert value <= schema["maximum"], f"{path}: above maximum"
        return

    if schema_type == "boolean":
        assert isinstance(value, bool), f"{path}: expected boolean"
        return

    if schema_type is None:
        # Allow partial schemas that only use refs/enum or intentionally omit type.
        return

    raise AssertionError(f"{path}: unsupported schema type {schema_type!r}")


def _operation(spec, path, method):
    return spec["paths"][path][method]


def _json_schema_from_media(op, status=None):
    if status is None:
        return op["requestBody"]["content"]["application/json"]["schema"]
    return op["responses"][status]["content"]["application/json"]["schema"]


def test_contract_metadata_and_required_paths():
    spec = _spec()

    assert spec["openapi"] == "3.1.0"
    assert spec["info"]["version"] == "v1"
    assert "SessionCookieAuth" in spec["components"]["securitySchemes"]

    session_auth = spec["components"]["securitySchemes"]["SessionCookieAuth"]
    assert session_auth["type"] == "apiKey"
    assert session_auth["in"] == "cookie"
    assert session_auth["name"] == "session_id"

    required = {
        ("/api/tenancy/v1/admin/tenants", "post"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}:suspend", "post"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}:rotate-credentials", "post"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}/audit-summary", "get"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}/diagnostics", "get"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}/timeline", "get"),
    }
    found = {(path, method) for path, path_item in spec["paths"].items() for method in path_item.keys()}
    for item in required:
        assert item in found, f"missing required operation {item}"


def test_contract_enforces_scope_and_no_authority_in_body():
    spec = _spec()
    create_schema = _resolve_ref(spec, "#/components/schemas/CreateTenantRequest")
    create_props = create_schema["properties"]

    # Body must not carry authoritative app scope or existing tenant authority.
    assert "appId" not in create_props
    assert "tenantId" not in create_props

    # Mutating operations should support idempotency keys for retry-safe flows.
    for path, method in [
        ("/api/tenancy/v1/admin/tenants", "post"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}:suspend", "post"),
        ("/api/tenancy/v1/admin/tenants/{tenantId}:rotate-credentials", "post"),
    ]:
        params = _operation(spec, path, method).get("parameters", [])
        param_refs = {p.get("$ref") for p in params if isinstance(p, dict)}
        assert "#/components/parameters/IdempotencyKeyHeader" in param_refs


def test_request_and_response_fixtures_match_contract_schemas():
    spec = _spec()

    fixture_map = [
        (
            FIXTURES_DIR / "create-tenant.request.json",
            _json_schema_from_media(_operation(spec, "/api/tenancy/v1/admin/tenants", "post")),
        ),
        (
            FIXTURES_DIR / "create-tenant.response.json",
            _json_schema_from_media(_operation(spec, "/api/tenancy/v1/admin/tenants", "post"), "201"),
        ),
        (
            FIXTURES_DIR / "suspend-tenant.request.json",
            _json_schema_from_media(_operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}:suspend", "post")),
        ),
        (
            FIXTURES_DIR / "suspend-tenant.response.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}:suspend", "post"),
                "200",
            ),
        ),
        (
            FIXTURES_DIR / "rotate-tenant-credentials.request.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}:rotate-credentials", "post")
            ),
        ),
        (
            FIXTURES_DIR / "rotate-tenant-credentials.response.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}:rotate-credentials", "post"),
                "200",
            ),
        ),
        (
            FIXTURES_DIR / "fetch-tenant-audit-summary.response.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}/audit-summary", "get"),
                "200",
            ),
        ),
        (
            FIXTURES_DIR / "fetch-tenant-diagnostics.response.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}/diagnostics", "get"),
                "200",
            ),
        ),
        (
            FIXTURES_DIR / "fetch-tenant-timeline.response.json",
            _json_schema_from_media(
                _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}/timeline", "get"),
                "200",
            ),
        ),
    ]

    for fixture_path, schema in fixture_map:
        data = _load_json(fixture_path)
        _assert_matches_schema(spec, schema, data, fixture_path.name)


def test_fetch_audit_summary_request_fixture_matches_parameter_contract():
    spec = _spec()
    request_fixture = _load_json(FIXTURES_DIR / "fetch-tenant-audit-summary.request.json")
    op = _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}/audit-summary", "get")

    assert request_fixture["path"]["tenantId"] == "acme-finance"

    params = {p["name"]: p for p in op["parameters"] if "name" in p}
    window_schema = params["windowHours"]["schema"]
    include_schema = params["includeActors"]["schema"]

    _assert_matches_schema(spec, window_schema, request_fixture["query"]["windowHours"], "$.query.windowHours")
    _assert_matches_schema(spec, include_schema, request_fixture["query"]["includeActors"], "$.query.includeActors")


def test_fetch_diagnostics_request_fixture_matches_parameter_contract():
    spec = _spec()
    request_fixture = _load_json(FIXTURES_DIR / "fetch-tenant-diagnostics.request.json")
    assert request_fixture["path"]["tenantId"] == "acme-finance"


def test_fetch_timeline_request_fixture_matches_parameter_contract():
    spec = _spec()
    request_fixture = _load_json(FIXTURES_DIR / "fetch-tenant-timeline.request.json")
    op = _operation(spec, "/api/tenancy/v1/admin/tenants/{tenantId}/timeline", "get")

    assert request_fixture["path"]["tenantId"] == "acme-finance"

    params = {p["name"]: p for p in op["parameters"] if "name" in p}
    limit_schema = params["limit"]["schema"]

    _assert_matches_schema(spec, limit_schema, request_fixture["query"]["limit"], "$.query.limit")
