---
name: Execution Issue
about: Single implementable work package for one agent/worktree
title: "<Stream>: <Execution task>"
labels: ["execution"]
assignees: []
---

## Context
- Why is this change needed?
- Which ADR/rule/roadmap item does this support?
- Parent tracker issue: #
- Roadmap item reference (if applicable): #

## Technical Detail
- Primary module/domain (`foundation` / `tools` / `runtime` / `governance` / `docs` / `ci`)
- Expected implementation approach (Terraform-native vs CLI pattern)
- Specific APIs/resources/patterns involved
- Constraints / non-goals

## Touched Paths (Expected)
- `terraform/...`
- `docs/...`

## Implementation Tasks
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3

## Acceptance Criteria
- [ ] Behavior / output is correct
- [ ] Validation commands pass
- [ ] Required docs updates included (if behavior/workflow changed)
- [ ] Issue/PR evidence posted

## Validation (Required Commands)
```bash
make preflight-session
```

## Labels / Queueing
- Status label: `ready` / `in-progress` / `blocked` / `review` / `done`
- Stream label (roadmap-aligned): e.g. `a0`, `a1`, `b0`
- Domain label (optional): e.g. `provider`, `docs`, `runtime`
- Priority label (optional): `p0` / `p1` / `p2` / `p3`

## Closure Condition
- [ ] PR opened and issue moved to `review`
- [ ] PR merged to `main`
- [ ] Other (state explicitly):

## Closeout Evidence (To Fill Before Done)
- PR:
- Commit SHA(s):
- Validation summary:
- Notes / follow-ups:
