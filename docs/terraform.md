## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.33.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | ~> 2.3 |
| <a name="requirement_http"></a> [http](#requirement\_http) | ~> 3.4 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.33.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_agentcore_bff"></a> [agentcore\_bff](#module\_agentcore\_bff) | ./modules/agentcore-bff | n/a |
| <a name="module_agentcore_foundation"></a> [agentcore\_foundation](#module\_agentcore\_foundation) | ./modules/agentcore-foundation | n/a |
| <a name="module_agentcore_governance"></a> [agentcore\_governance](#module\_agentcore\_governance) | ./modules/agentcore-governance | n/a |
| <a name="module_agentcore_runtime"></a> [agentcore\_runtime](#module\_agentcore\_runtime) | ./modules/agentcore-runtime | n/a |
| <a name="module_agentcore_tools"></a> [agentcore\_tools](#module\_agentcore\_tools) | ./modules/agentcore-tools | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [http_http.oidc_config](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent_dashboard_name"></a> [agent\_dashboard\_name](#input\_agent\_dashboard\_name) | Optional CloudWatch dashboard name override (defaults to <agent\_name>-dashboard when empty) | `string` | `""` | no |
| <a name="input_agent_name"></a> [agent\_name](#input\_agent\_name) | Name of the agent | `string` | n/a | yes |
| <a name="input_agentcore_region"></a> [agentcore\_region](#input\_agentcore\_region) | Optional AgentCore control-plane region override (defaults to region) | `string` | `""` | no |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | Optional SNS topic ARN for CloudWatch alarm notifications | `string` | `""` | no |
| <a name="input_app_id"></a> [app\_id](#input\_app\_id) | Application ID for multi-tenant isolation (North anchor). Defaults to agent\_name. | `string` | `""` | no |
| <a name="input_bedrock_region"></a> [bedrock\_region](#input\_bedrock\_region) | Optional Bedrock region override for model-related resources (defaults to agentcore\_region) | `string` | `""` | no |
| <a name="input_bff_acm_certificate_arn"></a> [bff\_acm\_certificate\_arn](#input\_bff\_acm\_certificate\_arn) | ARN of the ACM certificate for the custom domain. Must be in us-east-1 for CloudFront. | `string` | `""` | no |
| <a name="input_bff_agentcore_runtime_arn"></a> [bff\_agentcore\_runtime\_arn](#input\_bff\_agentcore\_runtime\_arn) | AgentCore runtime ARN for the BFF proxy (required if enable\_bff is true and enable\_runtime is false) | `string` | `""` | no |
| <a name="input_bff_agentcore_runtime_role_arn"></a> [bff\_agentcore\_runtime\_role\_arn](#input\_bff\_agentcore\_runtime\_role\_arn) | Optional runtime IAM role ARN for the BFF proxy to assume (set for cross-account runtime identity propagation) | `string` | `""` | no |
| <a name="input_bff_custom_domain_name"></a> [bff\_custom\_domain\_name](#input\_bff\_custom\_domain\_name) | Custom domain name for the BFF CloudFront distribution (e.g., agent.example.com). Requires bff\_acm\_certificate\_arn. | `string` | `""` | no |
| <a name="input_bff_region"></a> [bff\_region](#input\_bff\_region) | Optional BFF/API Gateway region override (defaults to agentcore\_region) | `string` | `""` | no |
| <a name="input_browser_network_mode"></a> [browser\_network\_mode](#input\_browser\_network\_mode) | Network mode for browser (PUBLIC, SANDBOX, VPC) | `string` | `"SANDBOX"` | no |
| <a name="input_browser_recording_s3_bucket"></a> [browser\_recording\_s3\_bucket](#input\_browser\_recording\_s3\_bucket) | S3 bucket for browser session recordings | `string` | `""` | no |
| <a name="input_browser_vpc_config"></a> [browser\_vpc\_config](#input\_browser\_vpc\_config) | VPC configuration for browser | <pre>object({<br/>    subnet_ids          = list(string)<br/>    security_group_ids  = list(string)<br/>    associate_public_ip = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_cedar_policy_files"></a> [cedar\_policy\_files](#input\_cedar\_policy\_files) | Map of policy names to Cedar policy file paths | `map(string)` | `{}` | no |
| <a name="input_code_interpreter_network_mode"></a> [code\_interpreter\_network\_mode](#input\_code\_interpreter\_network\_mode) | Network mode for code interpreter (PUBLIC, SANDBOX, VPC) | `string` | `"SANDBOX"` | no |
| <a name="input_code_interpreter_vpc_config"></a> [code\_interpreter\_vpc\_config](#input\_code\_interpreter\_vpc\_config) | VPC configuration for code interpreter | <pre>object({<br/>    subnet_ids          = list(string)<br/>    security_group_ids  = list(string)<br/>    associate_public_ip = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_dashboard_region"></a> [dashboard\_region](#input\_dashboard\_region) | Optional dashboard widget/console region override (defaults to region when empty) | `string` | `""` | no |
| <a name="input_dashboard_widgets_override"></a> [dashboard\_widgets\_override](#input\_dashboard\_widgets\_override) | Optional JSON array string of CloudWatch dashboard widgets to replace the default widget set | `string` | `""` | no |
| <a name="input_deployment_bucket_name"></a> [deployment\_bucket\_name](#input\_deployment\_bucket\_name) | S3 bucket name for deployment artifacts | `string` | `""` | no |
| <a name="input_enable_agent_dashboards"></a> [enable\_agent\_dashboards](#input\_enable\_agent\_dashboards) | Enable Terraform-managed per-agent CloudWatch dashboards | `bool` | `false` | no |
| <a name="input_enable_bff"></a> [enable\_bff](#input\_enable\_bff) | Enable the Serverless SPA/BFF module | `bool` | `false` | no |
| <a name="input_enable_bff_audit_log_persistence"></a> [enable\_bff\_audit\_log\_persistence](#input\_enable\_bff\_audit\_log\_persistence) | Persist BFF proxy shadow audit logs to S3 and provision Athena/Glue query resources | `bool` | `false` | no |
| <a name="input_enable_browser"></a> [enable\_browser](#input\_enable\_browser) | Enable web browser tool | `bool` | `false` | no |
| <a name="input_enable_browser_recording"></a> [enable\_browser\_recording](#input\_enable\_browser\_recording) | Enable session recording for browser | `bool` | `false` | no |
| <a name="input_enable_code_interpreter"></a> [enable\_code\_interpreter](#input\_enable\_code\_interpreter) | Enable Python code interpreter | `bool` | `true` | no |
| <a name="input_enable_evaluations"></a> [enable\_evaluations](#input\_enable\_evaluations) | Enable agent evaluation system | `bool` | `false` | no |
| <a name="input_enable_gateway"></a> [enable\_gateway](#input\_enable\_gateway) | Enable MCP gateway for tool integration | `bool` | `true` | no |
| <a name="input_enable_guardrails"></a> [enable\_guardrails](#input\_enable\_guardrails) | Enable Bedrock Guardrails | `bool` | `false` | no |
| <a name="input_enable_identity"></a> [enable\_identity](#input\_enable\_identity) | Enable workload identity | `bool` | `false` | no |
| <a name="input_enable_inference_profile"></a> [enable\_inference\_profile](#input\_enable\_inference\_profile) | Enable Bedrock application inference profile creation | `bool` | `false` | no |
| <a name="input_enable_kms"></a> [enable\_kms](#input\_enable\_kms) | Enable KMS encryption for logs and artifacts | `bool` | `false` | no |
| <a name="input_enable_memory"></a> [enable\_memory](#input\_enable\_memory) | Enable agent memory | `bool` | `false` | no |
| <a name="input_enable_observability"></a> [enable\_observability](#input\_enable\_observability) | Enable CloudWatch and X-Ray observability | `bool` | `true` | no |
| <a name="input_enable_packaging"></a> [enable\_packaging](#input\_enable\_packaging) | Enable two-stage build process | `bool` | `true` | no |
| <a name="input_enable_policy_engine"></a> [enable\_policy\_engine](#input\_enable\_policy\_engine) | Enable Cedar policy engine | `bool` | `false` | no |
| <a name="input_enable_runtime"></a> [enable\_runtime](#input\_enable\_runtime) | Enable agent runtime | `bool` | `true` | no |
| <a name="input_enable_s3_encryption"></a> [enable\_s3\_encryption](#input\_enable\_s3\_encryption) | Enable S3 encryption | `bool` | `true` | no |
| <a name="input_enable_waf"></a> [enable\_waf](#input\_enable\_waf) | Enable WAF protection for API Gateway | `bool` | `false` | no |
| <a name="input_enable_xray"></a> [enable\_xray](#input\_enable\_xray) | Enable X-Ray tracing | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | `"dev"` | no |
| <a name="input_evaluation_criteria"></a> [evaluation\_criteria](#input\_evaluation\_criteria) | Evaluation criteria as JSON | `map(string)` | `{}` | no |
| <a name="input_evaluation_prompt"></a> [evaluation\_prompt](#input\_evaluation\_prompt) | Prompt for agent evaluator | `string` | `"Evaluate the agent's response for correctness and relevance."` | no |
| <a name="input_evaluation_type"></a> [evaluation\_type](#input\_evaluation\_type) | Type of evaluations (TOOL\_CALL, REASONING, RESPONSE, or ALL) | `string` | `"TOOL_CALL"` | no |
| <a name="input_evaluator_model_id"></a> [evaluator\_model\_id](#input\_evaluator\_model\_id) | Model ID for evaluator | `string` | `"anthropic.claude-sonnet-4-5"` | no |
| <a name="input_evaluator_role_arn"></a> [evaluator\_role\_arn](#input\_evaluator\_role\_arn) | IAM role ARN for evaluator | `string` | `""` | no |
| <a name="input_gateway_name"></a> [gateway\_name](#input\_gateway\_name) | Name for the gateway | `string` | `""` | no |
| <a name="input_gateway_role_arn"></a> [gateway\_role\_arn](#input\_gateway\_role\_arn) | IAM role ARN for the gateway (if not provided, one will be created) | `string` | `""` | no |
| <a name="input_gateway_search_type"></a> [gateway\_search\_type](#input\_gateway\_search\_type) | Search type for gateway (SEMANTIC, HYBRID) | `string` | `"HYBRID"` | no |
| <a name="input_guardrail_blocked_input_messaging"></a> [guardrail\_blocked\_input\_messaging](#input\_guardrail\_blocked\_input\_messaging) | Message to return when input is blocked by guardrail | `string` | `"I'm sorry, I cannot process this request due to safety policies."` | no |
| <a name="input_guardrail_blocked_outputs_messaging"></a> [guardrail\_blocked\_outputs\_messaging](#input\_guardrail\_blocked\_outputs\_messaging) | Message to return when output is blocked by guardrail | `string` | `"I'm sorry, I cannot provide a response due to safety policies."` | no |
| <a name="input_guardrail_description"></a> [guardrail\_description](#input\_guardrail\_description) | Description of the guardrail | `string` | `"AgentCore Bedrock Guardrail"` | no |
| <a name="input_guardrail_filters"></a> [guardrail\_filters](#input\_guardrail\_filters) | Content filters for the guardrail | <pre>list(object({<br/>    type            = string # HATE, INSULT, SEXUAL, VIOLENCE, MISCONDUCT, PROMPT_ATTACK<br/>    input_strength  = string # NONE, LOW, MEDIUM, HIGH<br/>    output_strength = string # NONE, LOW, MEDIUM, HIGH<br/>  }))</pre> | <pre>[<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "HIGH",<br/>    "type": "HATE"<br/>  },<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "HIGH",<br/>    "type": "INSULT"<br/>  },<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "HIGH",<br/>    "type": "SEXUAL"<br/>  },<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "HIGH",<br/>    "type": "VIOLENCE"<br/>  },<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "HIGH",<br/>    "type": "MISCONDUCT"<br/>  },<br/>  {<br/>    "input_strength": "HIGH",<br/>    "output_strength": "NONE",<br/>    "type": "PROMPT_ATTACK"<br/>  }<br/>]</pre> | no |
| <a name="input_guardrail_name"></a> [guardrail\_name](#input\_guardrail\_name) | Name of the guardrail | `string` | `""` | no |
| <a name="input_guardrail_sensitive_info_filters"></a> [guardrail\_sensitive\_info\_filters](#input\_guardrail\_sensitive\_info\_filters) | Sensitive information filters (PII) | <pre>list(object({<br/>    type   = string # EMAIL, ADDRESS, PHONE, etc.<br/>    action = string # BLOCK, ANONYMIZE<br/>  }))</pre> | `[]` | no |
| <a name="input_inference_profile_description"></a> [inference\_profile\_description](#input\_inference\_profile\_description) | Optional description for the inference profile | `string` | `""` | no |
| <a name="input_inference_profile_model_source_arn"></a> [inference\_profile\_model\_source\_arn](#input\_inference\_profile\_model\_source\_arn) | Model source ARN (foundation model ARN or system-defined inference profile ARN) | `string` | `""` | no |
| <a name="input_inference_profile_name"></a> [inference\_profile\_name](#input\_inference\_profile\_name) | Name for the Bedrock application inference profile | `string` | `""` | no |
| <a name="input_inference_profile_tags"></a> [inference\_profile\_tags](#input\_inference\_profile\_tags) | Tags to apply to the inference profile | `map(string)` | `{}` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for encryption | `string` | `""` | no |
| <a name="input_lambda_architecture"></a> [lambda\_architecture](#input\_lambda\_architecture) | Architecture for agent runtime Lambda (x86\_64, arm64) | `string` | `"x86_64"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `30` | no |
| <a name="input_mcp_targets"></a> [mcp\_targets](#input\_mcp\_targets) | MCP targets configuration. Use alias ARNs for version pinning and rollback capability. Recommended: use module.mcp\_servers.mcp\_targets output. | <pre>map(object({<br/>    name        = string<br/>    lambda_arn  = string           # Should be alias ARN (arn:...:function:name:alias)<br/>    version     = optional(string) # Lambda version number for audit trail<br/>    description = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_memory_type"></a> [memory\_type](#input\_memory\_type) | Type of memory (SHORT\_TERM, LONG\_TERM, or BOTH) | `string` | `"BOTH"` | no |
| <a name="input_oauth_return_urls"></a> [oauth\_return\_urls](#input\_oauth\_return\_urls) | OAuth2 return URLs for workload identity | `list(string)` | `[]` | no |
| <a name="input_oidc_authorization_endpoint"></a> [oidc\_authorization\_endpoint](#input\_oidc\_authorization\_endpoint) | Override OIDC authorization endpoint (discovers if empty) | `string` | `""` | no |
| <a name="input_oidc_client_id"></a> [oidc\_client\_id](#input\_oidc\_client\_id) | OIDC Client ID | `string` | `""` | no |
| <a name="input_oidc_client_secret_arn"></a> [oidc\_client\_secret\_arn](#input\_oidc\_client\_secret\_arn) | Secrets Manager ARN for OIDC Client Secret | `string` | `""` | no |
| <a name="input_oidc_issuer"></a> [oidc\_issuer](#input\_oidc\_issuer) | OIDC Issuer URL | `string` | `""` | no |
| <a name="input_oidc_token_endpoint"></a> [oidc\_token\_endpoint](#input\_oidc\_token\_endpoint) | Override OIDC token endpoint (discovers if empty) | `string` | `""` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner identifier for resource tagging (team name, individual, or app ID). Applied as the Owner canonical tag. Defaults to app\_id (or agent\_name) when empty. | `string` | `""` | no |
| <a name="input_policy_engine_role_arn"></a> [policy\_engine\_role\_arn](#input\_policy\_engine\_role\_arn) | IAM role ARN for policy engine | `string` | `""` | no |
| <a name="input_policy_engine_schema"></a> [policy\_engine\_schema](#input\_policy\_engine\_schema) | Cedar schema definition for policy engine | `string` | `""` | no |
| <a name="input_proxy_reserved_concurrency"></a> [proxy\_reserved\_concurrency](#input\_proxy\_reserved\_concurrency) | Reserved concurrent executions for the BFF proxy Lambda | `number` | `10` | no |
| <a name="input_python_version"></a> [python\_version](#input\_python\_version) | Python version for packaging | `string` | `"3.12"` | no |
| <a name="input_region"></a> [region](#input\_region) | Default AWS region | `string` | `"us-east-1"` | no |
| <a name="input_runtime_config"></a> [runtime\_config](#input\_runtime\_config) | Runtime configuration as JSON | `map(any)` | `{}` | no |
| <a name="input_runtime_entry_file"></a> [runtime\_entry\_file](#input\_runtime\_entry\_file) | Entry point file for agent runtime | `string` | `"runtime.py"` | no |
| <a name="input_runtime_inline_policies"></a> [runtime\_inline\_policies](#input\_runtime\_inline\_policies) | Inline policies to attach to runtime role | `map(string)` | `{}` | no |
| <a name="input_runtime_policy_arns"></a> [runtime\_policy\_arns](#input\_runtime\_policy\_arns) | Additional IAM policy ARNs to attach to runtime role | `list(string)` | `[]` | no |
| <a name="input_runtime_reserved_concurrency"></a> [runtime\_reserved\_concurrency](#input\_runtime\_reserved\_concurrency) | Reserved concurrent executions for the agent runtime Lambda | `number` | `10` | no |
| <a name="input_runtime_role_arn"></a> [runtime\_role\_arn](#input\_runtime\_role\_arn) | IAM role ARN for agent runtime | `string` | `""` | no |
| <a name="input_runtime_source_path"></a> [runtime\_source\_path](#input\_runtime\_source\_path) | Path to agent source code directory | `string` | `"./agent-code"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources. Canonical tags (AppID, Environment, AgentName, ManagedBy, Owner) are always merged by the root module; values here supplement or override non-canonical keys only. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agentcore_bff_api_url"></a> [agentcore\_bff\_api\_url](#output\_agentcore\_bff\_api\_url) | BFF API URL |
| <a name="output_agentcore_bff_audit_logs_athena_database"></a> [agentcore\_bff\_audit\_logs\_athena\_database](#output\_agentcore\_bff\_audit\_logs\_athena\_database) | Athena/Glue database for BFF proxy audit logs |
| <a name="output_agentcore_bff_audit_logs_athena_table"></a> [agentcore\_bff\_audit\_logs\_athena\_table](#output\_agentcore\_bff\_audit\_logs\_athena\_table) | Athena/Glue table for BFF proxy audit logs |
| <a name="output_agentcore_bff_audit_logs_athena_workgroup"></a> [agentcore\_bff\_audit\_logs\_athena\_workgroup](#output\_agentcore\_bff\_audit\_logs\_athena\_workgroup) | Athena workgroup for BFF proxy audit logs |
| <a name="output_agentcore_bff_audit_logs_s3_prefix"></a> [agentcore\_bff\_audit\_logs\_s3\_prefix](#output\_agentcore\_bff\_audit\_logs\_s3\_prefix) | S3 prefix for BFF proxy audit shadow JSON logs |
| <a name="output_agentcore_bff_authorizer_id"></a> [agentcore\_bff\_authorizer\_id](#output\_agentcore\_bff\_authorizer\_id) | Authorizer ID |
| <a name="output_agentcore_bff_rest_api_id"></a> [agentcore\_bff\_rest\_api\_id](#output\_agentcore\_bff\_rest\_api\_id) | REST API ID |
| <a name="output_agentcore_bff_session_table_name"></a> [agentcore\_bff\_session\_table\_name](#output\_agentcore\_bff\_session\_table\_name) | DynamoDB Session Table |
| <a name="output_agentcore_bff_spa_url"></a> [agentcore\_bff\_spa\_url](#output\_agentcore\_bff\_spa\_url) | SPA URL |
| <a name="output_agentcore_dashboard_console_url"></a> [agentcore\_dashboard\_console\_url](#output\_agentcore\_dashboard\_console\_url) | CloudWatch console URL for the per-agent dashboard |
| <a name="output_agentcore_dashboard_name"></a> [agentcore\_dashboard\_name](#output\_agentcore\_dashboard\_name) | CloudWatch dashboard name for per-agent observability |
| <a name="output_agentcore_gateway_arn"></a> [agentcore\_gateway\_arn](#output\_agentcore\_gateway\_arn) | AgentCore gateway ARN (useful for cross-account target policies) |
| <a name="output_agentcore_gateway_role_arn"></a> [agentcore\_gateway\_role\_arn](#output\_agentcore\_gateway\_role\_arn) | AgentCore gateway service role ARN (useful for cross-account Lambda resource policies) |
| <a name="output_agentcore_inference_profile_arn"></a> [agentcore\_inference\_profile\_arn](#output\_agentcore\_inference\_profile\_arn) | Bedrock application inference profile ARN for per-agent cost isolation |
| <a name="output_agentcore_runtime_arn"></a> [agentcore\_runtime\_arn](#output\_agentcore\_runtime\_arn) | AgentCore runtime ARN |
