# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Automated `make validate-version-metadata` guard (with CI + pre-commit enforcement) to keep `VERSION`, `CHANGELOG.md`, and docs version metadata aligned (Issue #103).
- Policy and tag conformance report generation via `make policy-report` (Issue #61).
- Automated IAM wildcard and tag taxonomy inventory script `terraform/scripts/generate_policy_conformance_report.py`.
- Baseline governance report published at `docs/POLICY_CONFORMANCE_REPORT.md`.
- Custom domain and ACM certificate support for the BFF CloudFront distribution (Issue #53).
- MCP Tools OpenAPI 3.1.0 specification generation from the tool registry in `examples/mcp-servers/` (Issue #33).
- New `make generate-openapi` target in root `Makefile` to update the specification file at `docs/api/mcp-tools-v1.openapi.json`.
- Resource Coverage Matrix (`docs/NOVATION_MATRIX.md`) identifying migration candidates from CLI to native Terraform (Issue #17).
- AWS Provider version pin to `~> 6.33.0` to support native Bedrock AgentCore resources (Issue #17).
- Cedar tenant isolation policy (`tenant-isolation.cedar`) enforcing `principal.tenant_id == resource.tenant_id` and explicitly denying cross-tenant access (Issue #24, Rule 14.3).
- Negative automated tests for cross-tenant session forgery, expired sessions, and malformed composite cookies in the BFF authorizer (Issue #24, Rule 14.1).
- Claim-mismatch tests in the BFF proxy verifying that `AssumeRole` is not called when `tenant_id` or `app_id` is absent from the authorizer context (Issue #24, Rule 14.3).

### Fixed
- CLI provisioners in foundation/tools/runtime/governance modules now create `${path.module}/.terraform` before writing local output artifacts, preventing deploy failures on clean CI runners.
- Validation coverage now asserts this output-directory guard across all CLI-managed modules.

## [0.1.1] - 2026-02-25

### Changed
- Switched the documented EU quickstart default region to `eu-central-1` (Frankfurt) and added guidance about AgentCore feature coverage differences across regions (including London/Dublin/Frankfurt caveats).
- Renamed frontend Playwright npm/Makefile test commands from accessibility-specific names to generic frontend test names.

### Removed
- Disabled GitHub accessibility workflow and Axe-based accessibility regression spec/dependency from the frontend Playwright test harness.

## [0.1.0] - 2026-02-19

### Added
- Canonical repository version file (`VERSION`) for SemVer release control.
- Policy and linting rules to keep `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` synchronized.
- Pre-commit guard to block committing ephemeral `.scratch/` files.

### Changed
- Standardized project/package examples on pre-1.0 release line (`0.1.x`).
- Clarified release guidance as tag-first (`vMAJOR.MINOR.PATCH`) with optional short-lived release branch.
