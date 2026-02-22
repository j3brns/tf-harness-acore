# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Resource Coverage Matrix (`docs/NOVATION_MATRIX.md`) identifying migration candidates from CLI to native Terraform (Issue #17).
- AWS Provider version pin to `~> 6.33.0` to support native Bedrock AgentCore resources (Issue #17).

### Fixed
- CLI provisioners in foundation/tools/runtime/governance modules now create `${path.module}/.terraform` before writing local output artifacts, preventing deploy failures on clean CI runners.
- Validation coverage now asserts this output-directory guard across all CLI-managed modules.

## [0.1.0] - 2026-02-19

### Added
- Canonical repository version file (`VERSION`) for SemVer release control.
- Policy and linting rules to keep `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` synchronized.
- Pre-commit guard to block committing ephemeral `.scratch/` files.

### Changed
- Standardized project/package examples on pre-1.0 release line (`0.1.x`).
- Clarified release guidance as tag-first (`vMAJOR.MINOR.PATCH`) with optional short-lived release branch.
