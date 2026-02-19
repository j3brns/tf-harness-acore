# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Fixed
- Runtime and inference-profile CLI provisioners now create `${path.module}/.terraform` before writing JSON output artifacts, preventing deploy failures on clean CI runners.

## [0.1.0] - 2026-02-19

### Added
- Canonical repository version file (`VERSION`) for SemVer release control.
- Policy and linting rules to keep `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` synchronized.
- Pre-commit guard to block committing ephemeral `.scratch/` files.

### Changed
- Standardized project/package examples on pre-1.0 release line (`0.1.x`).
- Clarified release guidance as tag-first (`vMAJOR.MINOR.PATCH`) with optional short-lived release branch.
