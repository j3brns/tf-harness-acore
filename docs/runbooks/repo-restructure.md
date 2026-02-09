# Repository Restructure Plan (Terraform Subfolder)

## Scope
This runbook defines the preflight tests, orphaned-file review process, and checkpoint commits for moving Terraform core into `terraform/` while keeping `examples/` adjacent at repo root. Docs remain at repo root.

## Preflight Tests (Run Before Any Move)
### Windows (minimal, no bash)
```bat
validate_windows.bat --fix
```

### Bash/WSL (full checks)
```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform/scripts/validate_examples.sh
terraform/tests/security/tflint_scan.sh
terraform/tests/security/checkov_scan.sh
uv tool run pre-commit run --all-files
```

## Orphaned Files Review (Process + Candidates)
### Process
1. Build an inventory list of top-level docs and plans.
2. For each file, locate references with `rg -n "<filename>" .`.
3. Decide: Keep, Merge, Archive, or Delete.
4. If merging, update the primary doc and note the merge in the commit message.
5. If archiving, move to `docs/archive/` and update any references.

### Candidate Inventory (Initial Pass)
Keep (active or required):
- `README.md`
- `DEVELOPER_GUIDE.md`
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- `docs/architecture.md`, `docs/adr/`*, `docs/runbooks/`
- `examples/`

Review / Merge / Possibly Archive:
- `INDEX.md` (likely overlaps README/DEVELOPER_GUIDE)
- `QUICK_REFERENCE.md` (likely overlaps README)
- `SETUP.md` (merge into README/DEVELOPER_GUIDE)

Archive (historical or superseded):
- `README.old.md`
- `README_IMPROVEMENT_PLAN.md`
- `README_SUGGESTIONS_V2.md`
- `IMPLEMENTATION_PLAN.md`
- `IMPLEMENTATION_SUMMARY.md`
- `DELIVERY_SUMMARY.txt`
- `SECURITY_AUDIT_2026-02-08.md` (move to `docs/audits/` if kept)

Delete (only after confirming no references):
- Any duplicate plan doc after merge + archive

## Target Layout (After Move)
```
repo-root/
  docs/
  examples/
  terraform/
    main.tf
    variables.tf
    outputs.tf
    versions.tf
    terraform.tfvars.example
    modules/
    scripts/
    tests/
  README.md
  DEVELOPER_GUIDE.md
  AGENTS.md
```

## Move Plan (High-Level)
1. Create `terraform/` and move core Terraform files + `modules/`, `scripts/`, `tests/`.
2. Update references in docs and scripts to new paths.
3. Update `Makefile` and `validate_windows.bat` to run from `terraform/`.
4. Run preflight tests again from repo root (and from `terraform/` where needed).

## Checkpoint Commit Plan
1. `docs: add repo restructure runbook and preflight checklist`
2. `docs: update agent rules for repo layout and reorg guardrails`
3. `chore: move terraform core into terraform/`
4. `chore: update paths and scripts after terraform move`
5. `docs: archive or merge redundant docs` + `chore: cleanup references`
6. `chore: post-move validation notes`

## Notes
- Examples remain at repo root. Do not move them into `terraform/`.
- Docs remain at repo root. Do not move docs under `terraform/`.
- Always rerun preflight tests after each checkpoint.
