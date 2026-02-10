output "spa_url" {
  description = "URL of the SPA (CloudFront)"
  value       = var.enable_bff ? "https://${aws_cloudfront_distribution.bff[0].domain_name}" : ""
}

output "api_url" {
  description = "Direct URL of the API Gateway (for debugging)"
  value       = var.enable_bff ? "${aws_api_gateway_stage.bff[0].invoke_url}" : ""
}

output "session_table_name" {
  description = "Name of the DynamoDB Session Table"
  value       = var.enable_bff ? aws_dynamodb_table.sessions[0].name : ""
}
