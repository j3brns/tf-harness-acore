# Runbook: Env-Only to Segmented Terraform State Key Migration

## Purpose

This runbook defines the migration procedure for moving Terraform S3 backend state keys from the
current CI env-only pattern:

- Legacy (current CI): `agentcore/${CI_ENVIRONMENT_NAME}/terraform.tfstate`

to the E8A target segmented pattern (ADR 0013):

- Target: `agentcore/${CI_ENVIRONMENT_NAME}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate`

The bucket model does not change (one backend bucket per environment/account). Only the object key path changes.

## Scope

In scope:
- S3 backend key migration within an existing environment bucket/account
- Native S3 locking path changes (`.tflock`) that follow the key automatically
- Dev/test/prod rollout sequencing and evidence capture
- CI key-rendering validation and operator evidence requirements

Out of scope:
- Switching from separate backends to Terraform workspaces (forbidden by ADR 0006)
- Changing bucket names/accounts/regions as part of the same change
- Manual state JSON edits
- Introducing Terragrunt (evaluated and deferred in ADR 0013 / Issue #73)

## Canonical Strategy (Design)

### Key Format

Use this backend key format for the standard root Terraform stack:

```text
agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate
```

Examples:
- `agentcore/dev/research-console/research-agent-core-a1b2/terraform.tfstate`
- `agentcore/test/ops-assistant/ops-assistant-core-f9e1/terraform.tfstate`

### Why Segment Beyond `{env}`?

The bucket boundary remains the primary blast-radius control. App/agent segmentation adds:
- clearer operator visibility in S3 listings and recovery commands,
- less lock contention within the same environment backend bucket,
- consistent pathing for lock files tied to a specific deployment unit,
- a stable convention for runbooks and CI templates,
- safer parallelism as the repo grows beyond one agent per environment.

### CI Input Contract (Required Before `terraform init`)

E8B (`#74`) must have these values available before backend initialization:

- `CI_ENVIRONMENT_NAME`
- `TF_STATE_BUCKET`
- `AWS_DEFAULT_REGION`
- `TF_STATE_APP_ID` (slug-safe)
- `TF_STATE_AGENT_NAME` (slug-safe)

Derived key:

```text
agentcore/${CI_ENVIRONMENT_NAME}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate
```

### Non-Goals / Guardrails

- Do not introduce branch-, PR-, or developer-specific keys in shared environment backends.
- Do not mix backend bucket moves and key moves in one execution issue.
- Do not silently change region defaults as part of the state-key migration.
- Do not run concurrent Terraform operations during migration.

## Preconditions

1. The execution issue/worktree is scoped to backend key migration work only.
2. `make preflight-session` passes (Rule 7.7).
3. The target environment is known (`dev`, `test`, or `prod`) and matches the backend file being edited/generated.
4. No concurrent CI/local Terraform operations are running against the same backend.
5. S3 versioning is enabled on the state bucket (expected per ADR 0004).
6. CI/job inputs for `app_id` and `agent_name` are known and can be rendered to backend-key-safe values.

## Pre-Flight Checklist (Mandatory)

Run from repo root unless noted.

1. Session preflight

```bash
make preflight-session
```

2. Create scratch evidence folder (do not commit)

```bash
mkdir -p .scratch/state-key-migration
```

3. Export the environment and state bucket details

```bash
export ENV="<dev|test|prod>"
export TF_STATE_BUCKET="terraform-state-${ENV}-<account-or-project-id>"
export TF_STATE_APP_ID="<app-id-slug>"
export TF_STATE_AGENT_NAME="<agent-name-slug>"
export LEGACY_STATE_KEY="agentcore/${ENV}/terraform.tfstate"
export SEGMENTED_STATE_KEY="agentcore/${ENV}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate"
```

4. Capture a local state backup before backend migration

```bash
terraform -chdir=terraform state pull > .scratch/state-key-migration/$(date +%Y%m%d-%H%M%S)-${ENV}-pre-key-migration.tfstate
sha256sum .scratch/state-key-migration/*-${ENV}-pre-key-migration.tfstate
```

5. Render and review the new backend key (evidence for E8A/E8B handoff)

```bash
printf 'legacy=%s\nnew=%s\n' "${LEGACY_STATE_KEY}" "${SEGMENTED_STATE_KEY}"
```

6. Confirm the current remote object exists (legacy key)

```bash
aws s3api head-object \
  --bucket "${TF_STATE_BUCKET}" \
  --key "${LEGACY_STATE_KEY}"
```

7. Baseline plan (stop on unexpected drift)

```bash
terraform -chdir=terraform plan \
  -refresh-only \
  -var-file=../examples/research-agent.tfvars
```

## Migration Procedure (Per Environment)

### 1. Update Backend Config to the Segmented Key

E8B will update the CI-generated backend config in `.gitlab-ci.yml` (not this runbook issue).
For manual/simulated migration rehearsal, ensure the backend config for the environment uses:

```hcl
key = "agentcore/<env>/<app-id>/<agent-name>/terraform.tfstate"
```

### 2. Migrate Backend State Using Terraform (Preferred)

Run `terraform init` with backend migration enabled after updating the backend config:

```bash
terraform -chdir=terraform init \
  -reconfigure \
  -migrate-state \
  -backend-config=backend-${ENV}.tf
```

Notes:
- Terraform copies/moves backend state metadata to the new key location.
- The lock file path will follow the new key automatically when future operations run.
- Do not manually copy state objects unless Terraform migration fails and you are executing break-glass recovery.

### 3. Verify the New State Key Exists

```bash
aws s3api head-object \
  --bucket "${TF_STATE_BUCKET}" \
  --key "${SEGMENTED_STATE_KEY}"
```

Optional: confirm the legacy object remains only as historical rollback material until the migration is fully validated.

```bash
aws s3api list-object-versions \
  --bucket "${TF_STATE_BUCKET}" \
  --prefix "agentcore/"
```

### 4. Validate Terraform Behavior After Migration

```bash
terraform -chdir=terraform plan \
  -refresh-only \
  -var-file=../examples/research-agent.tfvars

terraform -chdir=terraform plan \
  -var-file=../examples/research-agent.tfvars
```

Gate:
- Stop if the post-migration plan shows unexpected drift or replacement unrelated to the backend key move.

### 5. Capture Evidence for Issue / PR Closeout

Record:
- environment migrated,
- backend config key before/after,
- commands run,
- `head-object` success for `agentcore/${ENV}/terraform.tfstate`,
- `head-object` success for the new segmented key,
- post-migration plan outcome,
- CI links (if migration change is applied via pipeline).

## E8A / E8B Handoff Notes

- E8A (`#73`) produces the strategy/decision and this runbook only. It does not execute live backend migrations.
- E8B (`#74`) implements CI backend key rendering and runs migrations per environment using this runbook.
- Terragrunt adoption is explicitly deferred for E8B (see `docs/adr/0013-segmented-state-key-strategy.md`).

## Rollout Order (Recommended)

1. `dev`
2. `test`
3. `prod`

Do not start the next environment until the previous environment:
- passes post-migration validation,
- has evidence recorded,
- has no active backend lock or concurrent pipeline activity.

## Rollback (If Migration Fails)

Preferred rollback:
1. Restore backend config key to the previous value.
2. Re-run `terraform init -reconfigure -migrate-state -backend-config=backend-${ENV}.tf` to move the backend pointer/state back.

Break-glass rollback (only if Terraform migration is not usable):
- restore the prior S3 object version using bucket versioning,
- reinitialize Terraform,
- run `terraform plan` to confirm consistency.

Never manually edit the state JSON.

## CI/CD Notes

- If GitLab CI or local scripts generate backend config files dynamically, update the generated `key` value to `agentcore/${ENV}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate` before running `terraform init`.
- Freeze overlapping deploy jobs during the migration window to avoid lock contention and split-brain state writes.

## Related References

- `docs/adr/0004-state-management.md`
- `docs/adr/0006-separate-backends-not-workspaces.md`
- `docs/adr/0013-segmented-state-key-strategy.md`
- `docs/runbooks/state-recovery.md`
- `.gitlab-ci.yml` (backend generation template)
