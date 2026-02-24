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
- Actor / persona primarily affected (e.g. Agent Developer, Platform Maintainer, Tenant Admin, CI/Promotion Pipeline)
- Entity boundary touched (`AppID`, `TenantID`, `AgentName`, `Environment`, `SessionID`, metadata plane)
- Plane(s) affected (`runtime`, `control`, `CI/release`, `observability`)
- Primary module/domain (`foundation` / `tools` / `runtime` / `governance` / `docs` / `ci`)
- Expected implementation approach (Terraform-native vs CLI pattern)
- Specific APIs/resources/patterns involved
- Constraints / non-goals
- Inbound identity impact (if any)
- Outbound identity impact (if any)
- Cross-boundary escalation required? (If yes, record escalation target and reason)

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
- Stream lane label (roadmap-aligned): `a` / `b` / `c` / `d` / `e`
- Roadmap item label (optional): e.g. `a0`, `a1`, `b0`
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
