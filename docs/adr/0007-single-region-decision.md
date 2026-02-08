# ADR 0007: Single Region Deployment

## Status

Accepted

## Context

AWS Bedrock AgentCore can be deployed in multiple regions. Need to decide deployment topology:
- Single region (us-east-1)
- Multi-region active-passive
- Multi-region active-active

## Decision

Deploy to single region (us-east-1) initially.

Document DR region (us-west-2) for future expansion but do not implement multi-region until required.

## Rationale

### Cost vs Complexity Tradeoff

| Topology | Monthly Cost | Complexity | RTO |
|----------|-------------|------------|-----|
| Single region | $X | Low | Hours |
| Active-passive | ~1.5X | Medium | Minutes |
| Active-active | ~2X | High | Seconds |

### Current Requirements
- No SLA requiring <1 hour RTO
- Budget constraints favor simplicity
- Team expertise in single-region patterns
- Bedrock AgentCore still in preview (limited region availability)

### Why us-east-1?
- Full Bedrock AgentCore feature availability
- Lowest latency for primary users (East Coast)
- Most AWS services launch here first
- Lower data transfer costs (majority of traffic origin)

## Disaster Recovery Plan

### Documented but Not Implemented

**DR Region**: us-west-2

**Recovery Steps** (manual):
1. Deploy infrastructure to us-west-2 from Git
2. Restore state from S3 cross-region replication (if enabled)
3. Update DNS to point to new region
4. Notify users of cutover

**RTO Estimate**: 2-4 hours
**RPO Estimate**: Last state backup (varies)

## Consequences

### Positive
- Simpler infrastructure
- Lower costs
- Easier debugging (single region to check)
- No cross-region data replication complexity
- Faster deployments

### Negative
- Single point of failure (region outage = full outage)
- No automatic failover
- Manual DR process
- Dependent on us-east-1 availability

## Future Multi-Region Triggers

Consider implementing multi-region when:
- [ ] SLA requires <15 minute RTO
- [ ] Regulatory requirements mandate geographic redundancy
- [ ] User base becomes geographically distributed
- [ ] Budget allows 2x infrastructure cost
- [ ] Team has capacity for additional operational complexity

## Implementation Notes

### State Backup (Recommended)

Enable cross-region replication for state bucket:

```hcl
resource "aws_s3_bucket_replication_configuration" "state_dr" {
  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "dr-replication"
    status = "Enabled"

    destination {
      bucket        = "arn:aws:s3:::terraform-state-dr-us-west-2"
      storage_class = "STANDARD"
    }
  }
}
```

### Runbook Reference

See `docs/runbooks/regional-failover.md` for manual DR procedure.

## Alternatives Considered

1. **Multi-region active-active** - Rejected (cost, complexity, not required)
2. **Multi-region active-passive** - Deferred (document for future)
3. **us-west-2 primary** - Rejected (higher latency for primary users)

## References

- [AWS Regional Availability](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/)
- [Bedrock AgentCore Regions](https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-regions.html)
- [Disaster Recovery Patterns](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/plan-for-disaster-recovery-dr.html)
