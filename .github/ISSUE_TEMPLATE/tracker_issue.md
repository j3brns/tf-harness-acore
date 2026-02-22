---
name: Tracker Issue
about: Coordination/tracking issue for a larger initiative with child execution issues
title: "<Stream>: <Initiative / tracker>"
labels: ["tracker"]
assignees: []
---

## Context
- Why is this initiative needed?
- Which ADR/rules/roadmap goals does it advance?
- Roadmap item(s): #

## Technical Detail
- Scope boundaries
- Key technical decisions / assumptions
- Risks / blockers likely to affect sequencing
- Non-goals for this tracker

## Child Execution Issues (Rule 12.1 structure required)
- [ ] #<issue> Child task 1
- [ ] #<issue> Child task 2
- [ ] #<issue> Child task 3

## Ordering / Dependencies
- Depends on:
- Can run in parallel:
- Must serialize (shared files / conflict risk):

## Active Allocations
- `#<issue>` -> `wt/<scope>/<issue>-<slug>` -> Agent/Owner

## Acceptance Criteria (Tracker Done)
- [ ] Child execution issues created/updated with full structure
- [ ] Dependencies / ordering documented
- [ ] Ready tasks labeled `ready`
- [ ] Active allocations recorded
- [ ] Blockers captured
- [ ] Tracker checklist/status updated

## Labels / Queueing
- Status label: `ready` / `in-progress` / `blocked` / `review` / `done` (for tracker workflow)
- Stream label (roadmap-aligned): e.g. `a0`, `a1`, `b0`
- Domain label(s) if useful
- Priority label (optional): `p0` / `p1` / `p2` / `p3`

## Closure Condition
- [ ] Child issues allocated and tracker updated
- [ ] PR merged (if tracker includes docs/planning implementation)
- [ ] Other (state explicitly):

## Handoff / Control Tower Notes
- Next ready issue:
- Current blockers:
- Evidence links (PRs, CI, docs):
