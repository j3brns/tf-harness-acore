# Runbook: Segmented Terraform State Key Migration (`agentcore/{env}/terraform.tfstate`)

## Purpose

This runbook defines the repo-standard strategy and migration procedure for moving Terraform S3 backend state keys from the legacy flat path:

- Legacy: `agentcore/terraform.tfstate`

to the segmented path used by the current backend examples:

- Target: `agentcore/{env}/terraform.tfstate`

This change keeps the same S3 backend bucket model (one bucket per environment) and only changes the object key path inside each bucket.

## Scope

In scope:
- S3 backend key migration within an existing environment bucket
- Native S3 locking path changes (`.tflock`) that follow the key automatically
- Dev/test/prod rollout sequencing and evidence capture

Out of scope:
- Switching from separate backends to Terraform workspaces (forbidden by ADR 0006)
- Changing bucket names/accounts/regions as part of the same change
- Manual state JSON edits

## Canonical Strategy (Design)

### Key Format

Use this backend key format for all standard environments:

```text
agentcore/{env}/terraform.tfstate
```

Examples:
- `agentcore/dev/terraform.tfstate`
- `agentcore/test/terraform.tfstate`
- `agentcore/prod/terraform.tfstate`

### Why Segment by `{env}` When Buckets Are Already Per-Environment?

The bucket boundary remains the primary blast-radius control. The segmented key adds:
- clearer operator visibility in S3 listings and recovery commands,
- consistent pathing for lock files (`agentcore/{env}/terraform.tfstate.tflock`),
- a stable convention for runbooks and CI templates,
- safer migration from older docs/examples that referenced a flat key.

### Non-Goals / Guardrails

- Do not introduce branch-, PR-, or developer-specific keys in shared environment backends.
- Do not mix backend bucket moves and key moves in one execution issue.
- Do not run concurrent Terraform operations during migration.

## Preconditions

1. The execution issue/worktree is scoped to backend key migration work only.
2. `make preflight-session` passes (Rule 7.7).
3. The target environment is known (`dev`, `test`, or `prod`) and matches the backend file being edited/generated.
4. No concurrent CI/local Terraform operations are running against the same backend.
5. S3 versioning is enabled on the state bucket (expected per ADR 0004).

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
export LEGACY_STATE_KEY="agentcore/terraform.tfstate"
export SEGMENTED_STATE_KEY="agentcore/${ENV}/terraform.tfstate"
```

4. Capture a local state backup before backend migration

```bash
terraform -chdir=terraform state pull > .scratch/state-key-migration/$(date +%Y%m%d-%H%M%S)-${ENV}-pre-key-migration.tfstate
sha256sum .scratch/state-key-migration/*-${ENV}-pre-key-migration.tfstate
```

5. Confirm the current remote object exists (legacy key)

```bash
aws s3api head-object \
  --bucket "${TF_STATE_BUCKET}" \
  --key "${LEGACY_STATE_KEY}"
```

6. Baseline plan (stop on unexpected drift)

```bash
terraform -chdir=terraform plan \
  -refresh-only \
  -var-file=../examples/research-agent.tfvars
```

## Migration Procedure (Per Environment)

### 1. Update Backend Config to the Segmented Key

Use the repo examples as the source of truth:
- `terraform/backend-dev.tf.example`
- `terraform/backend-test.tf.example`
- `terraform/backend-prod.tf.example`

Ensure the backend config for the environment uses:

```hcl
key = "agentcore/<env>/terraform.tfstate"
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
- post-migration plan outcome,
- CI links (if migration change is applied via pipeline).

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

- If GitLab CI or local scripts generate backend config files dynamically, update the generated `key` value to `agentcore/${ENV}/terraform.tfstate` before running `terraform init`.
- Freeze overlapping deploy jobs during the migration window to avoid lock contention and split-brain state writes.

## Related References

- `docs/adr/0004-state-management.md`
- `docs/adr/0006-separate-backends-not-workspaces.md`
- `docs/runbooks/state-recovery.md`
- `terraform/backend-dev.tf.example`
- `terraform/backend-test.tf.example`
- `terraform/backend-prod.tf.example`
