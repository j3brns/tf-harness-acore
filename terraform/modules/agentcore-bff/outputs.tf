output "spa_url" {
  description = "URL of the SPA (CloudFront)"
  value       = var.enable_bff ? "https://${aws_cloudfront_distribution.bff[0].domain_name}" : ""
}

output "api_url" {
  description = "Direct URL of the API Gateway (for debugging)"
  value       = var.enable_bff ? aws_api_gateway_stage.bff[0].invoke_url : ""
}

output "session_table_name" {
  description = "Name of the DynamoDB Session Table"
  value       = var.enable_bff ? aws_dynamodb_table.sessions[0].name : ""
}

output "rest_api_id" {
  description = "ID of the REST API"
  value       = var.enable_bff ? aws_api_gateway_rest_api.bff[0].id : ""
}

output "authorizer_id" {
  description = "ID of the Lambda Authorizer"
  value       = var.enable_bff ? aws_api_gateway_authorizer.token_handler[0].id : ""
}

output "audit_logs_s3_prefix" {
  description = "S3 prefix for BFF proxy audit shadow JSON logs"
  value       = local.audit_logs_enabled ? local.audit_logs_events_prefix : ""
}

output "audit_logs_athena_database" {
  description = "Glue/Athena database name for BFF proxy audit logs"
  value       = local.audit_logs_enabled ? aws_glue_catalog_database.bff_audit_logs[0].name : ""
}

output "audit_logs_athena_table" {
  description = "Glue/Athena table name for BFF proxy audit logs"
  value       = local.audit_logs_enabled ? aws_glue_catalog_table.bff_audit_logs[0].name : ""
}

output "audit_logs_athena_workgroup" {
  description = "Athena workgroup name for BFF proxy audit log queries"
  value       = local.audit_logs_enabled ? aws_athena_workgroup.bff_audit_logs[0].name : ""
}
