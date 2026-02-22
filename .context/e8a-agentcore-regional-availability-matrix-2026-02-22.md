# E8A AgentCore Regional Availability Matrix (Issue #73)

Checked on: 2026-02-22

## Why This Exists (Repo Relevance)

Issue `#73` (E8A) requires a region-aware architecture handoff for segmented Terraform state keys and CI migration planning. This file captures the AWS Knowledge MCP-backed evidence used to document:

- the repo-relevant AgentCore service/capability regional availability matrix,
- region caveats that affect split-region deployment planning,
- the distinction between current CI region context (`AWS_DEFAULT_REGION`) and AgentCore placement (`agentcore_region`).

This is a curated synthesis for future execution quality (not a raw dump).

## AWS Knowledge MCP Queries Used

### Documentation search queries

- `Amazon Bedrock AgentCore regional availability runtime memory gateway identity browser code interpreter evaluator policy`
- `Amazon Bedrock AgentCore regions developer guide`
- `bedrock-agentcore limits quotas evaluations regions preview policy all AWS Regions`

### Documentation pages read

- `https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html`
- `https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/cross-region-inference.html`
- `https://docs.aws.amazon.com/general/latest/gr/bedrock_agentcore.html`

### Regional availability API checks (`get_regional_availability`, `resource_type="product"`)

Filters used:
- `Amazon Bedrock AgentCore`
- `Amazon Bedrock AgentCore Runtime`

Results captured:
- `eu-central-1`: `AgentCore=isAvailableIn`, `Runtime=isAvailableIn`
- `eu-west-1`: `AgentCore=isAvailableIn`, `Runtime=isAvailableIn`
- `eu-west-2`: `AgentCore=isAvailableIn`, `Runtime=isBeingPlannedIn`

## Sources (Primary)

- AWS AgentCore regions table: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html
- AWS AgentCore cross-region inference: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/cross-region-inference.html
- AWS General Reference AgentCore endpoints: https://docs.aws.amazon.com/general/latest/gr/bedrock_agentcore.html
- AWS What’s New (Policy + Evaluations preview context): https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-bedrock-agentcore-policy-evaluations-preview/

## Matrix (Repo-Relevant Capabilities)

Primary region assumed for E8A analysis: `eu-central-1` (Frankfurt) for AgentCore control-plane/runtime.
Comparison region for current CI default context: `eu-west-2` (London).

Legend:
- `Yes` = directly indicated in source
- `No` = not listed / blank in source table
- `Conflict` = sources disagree; treat as requiring preflight verification
- `Inference` = repo-topology classification inferred from sources + repo design

| Capability | `eu-central-1` | `eu-west-2` | Topology Classification | Key Caveats / Notes | Evidence Basis |
| --- | --- | --- | --- | --- | --- |
| AgentCore Runtime | Yes | **Conflict** | Primary-region service (Inference) | `agentcore-regions` shows London support, but AWS General Reference endpoints page omits `eu-west-2`, and AWS MCP product check reports Runtime `isBeingPlannedIn` in `eu-west-2` on 2026-02-22. Preflight-check Runtime endpoint/CLI before using London as AgentCore primary. | `agentcore-regions`, AWS General Reference endpoints, AWS MCP `get_regional_availability` |
| AgentCore Memory | Yes | Yes | Split-capable via CRIS (Inference) | Memory service is listed in London in `agentcore-regions`, but Memory CRIS Europe geography lists `eu-central-1` and `eu-west-1` (not `eu-west-2`) for inference routing. | `agentcore-regions`, `cross-region-inference` |
| AgentCore Gateway | Yes | **Conflict** | Primary-region service (Inference) | `agentcore-regions` shows London support, but the Gateway data plane endpoint table omits `eu-west-2`. Validate endpoint availability in-region before rollout. | `agentcore-regions`, AWS General Reference endpoints |
| AgentCore Identity | Yes | Yes | Primary-region service (Inference) | No separate endpoint table row by subfeature in AWS General Reference; rely on AgentCore feature region table. | `agentcore-regions` |
| AgentCore Observability | Yes | Yes | Primary-region service (Inference) | Region support shown in `agentcore-regions`; no separate subservice endpoint list used in this synthesis. | `agentcore-regions` |
| AgentCore Browser (repo maps under Built-in Tools) | Yes | Yes | Primary-region service (Inference) | `agentcore-regions` groups Browser + Code Interpreter under “Built-in Tools”; feature-specific rows are not split. | `agentcore-regions` |
| AgentCore Code Interpreter (repo maps under Built-in Tools) | Yes | Yes | Primary-region service (Inference) | Same caveat as Browser: grouped under “Built-in Tools” in the region table. | `agentcore-regions` |
| AgentCore Policy | Yes | No | Split-capable via CRIS (Inference) | `agentcore-regions` shows Policy in Frankfurt and blank in London; Policy CRIS Europe includes Frankfurt/Ireland/Paris/Stockholm/Milan/Spain (not London). | `agentcore-regions`, `cross-region-inference` |
| AgentCore Evaluations | Yes | No (service) / Yes (CRIS inference region) | Split-capable via CRIS (Inference) | `agentcore-regions` shows Evaluations in Frankfurt and blank in London, but Evaluations CRIS Europe includes London as an inference region. Distinguish control-plane/service region from inference routing geography. | `agentcore-regions`, `cross-region-inference` |

## Region Clarification for E8A Docs

- E8A does not change repo region defaults.
- `.gitlab-ci.yml` currently uses `AWS_DEFAULT_REGION=eu-west-2` for backend generation and general job AWS context.
- AgentCore placement remains a deploy-time input (`agentcore_region`) and may be `eu-central-1` in EU split deployments.
- CloudFront/ACM/WAF `us-east-1` exceptions are global-service concerns and are not part of the AgentCore capability matrix above.

## Recommended E8B Preflight Checks (Derived)

Before migrating CI backend keys in an environment, E8B should verify the target deployment topology explicitly:

1. Render and log the planned state key (env/app/agent).
2. Log `agentcore_region`, `bff_region`, and `bedrock_region`.
3. For the chosen `agentcore_region`, verify AgentCore control/data endpoint and at least one read/list command succeeds (`bedrock-agentcore-control`).
4. If using AgentCore Policy or Evaluations, verify feature support in that region (and CRIS expectations) before promotion.
