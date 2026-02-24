locals {
  agentcore_region = var.agentcore_region != "" ? var.agentcore_region : var.region

  audit_logs_enabled = var.enable_bff && var.enable_audit_log_persistence && trimspace(var.logging_bucket_id) != ""
  audit_logs_prefix  = "audit/bff-proxy"
  # CloudFront access logs require an S3 bucket DNS name. Reuse the shared logging bucket when configured.
  cloudfront_access_logs_bucket_domain = trimspace(var.logging_bucket_id) != "" ? "${var.logging_bucket_id}.s3.amazonaws.com" : aws_s3_bucket.spa[0].bucket_domain_name
  cloudfront_access_logs_prefix        = "cloudfront-access-logs/"

  audit_logs_events_prefix         = "${local.audit_logs_prefix}/events/"
  audit_logs_athena_results_prefix = "${local.audit_logs_prefix}/athena-results/"

  athena_name_suffix          = replace(lower("${var.agent_name}_${var.environment}"), "-", "_")
  audit_logs_athena_database  = "agentcore_bff_audit_${local.athena_name_suffix}"
  audit_logs_athena_table     = "proxy_shadow_json"
  audit_logs_athena_workgroup = "agentcore-bff-audit-${var.agent_name}-${var.environment}"
}
