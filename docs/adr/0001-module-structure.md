# ADR 0001: Four-Module Architecture Structure

## Status

Accepted

## Context

Need to organize AWS Bedrock AgentCore resources into logical, maintainable modules. The original implementation had only 1 module which became complex and hard to maintain. We need clear separation of concerns.

## Decision

Implement 4-module architecture:

1. **agentcore-foundation** (Gateway, Identity, Observability) - Terraform-native resources
2. **agentcore-tools** (Code Interpreter, Browser) - Terraform-native resources
3. **agentcore-runtime** (Runtime, Memory, Packaging) - CLI-based resources
4. **agentcore-governance** (Policies, Evaluations) - CLI-based resources

## Rationale

- Clear separation between Terraform-native vs CLI-based resources
- Foundation provides base infrastructure for other modules
- Tools are independent capabilities that can be enabled/disabled
- Runtime handles execution lifecycle
- Governance enforces security and quality

## Dependency Graph

```
agentcore-foundation (NO dependencies)
    |
    +---> agentcore-tools (depends: foundation)
    +---> agentcore-runtime (depends: foundation)
              |
          agentcore-governance (depends: foundation + runtime)
```

## Consequences

### Positive
- Modular, reusable components
- Clear dependency graph
- Easy to enable/disable features independently
- Better testability
- Easier code review (smaller scope per module)

### Negative
- More complex than single module
- Need to manage inter-module dependencies
- More files to navigate

## Alternatives Considered

1. **Single monolithic module** - Rejected (too complex, hard to maintain)
2. **9 separate modules (one per feature)** - Rejected (too granular, dependency management overhead)
3. **2 modules (native vs CLI)** - Rejected (loses semantic separation)
