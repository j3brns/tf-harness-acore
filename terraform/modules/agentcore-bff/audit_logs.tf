resource "aws_glue_catalog_database" "bff_audit_logs" {
  count = local.audit_logs_enabled ? 1 : 0
  name  = local.audit_logs_athena_database

  description = "Query catalog for BFF proxy audit shadow JSON logs (${var.agent_name}/${var.environment})"
}

resource "aws_glue_catalog_table" "bff_audit_logs" {
  count         = local.audit_logs_enabled ? 1 : 0
  name          = local.audit_logs_athena_table
  database_name = aws_glue_catalog_database.bff_audit_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL             = "TRUE"
    classification       = "json"
    "projection.enabled" = "false"
    "typeOfData"         = "file"
    "compressionType"    = "none"
  }

  storage_descriptor {
    location      = "s3://${var.logging_bucket_id}/${local.audit_logs_events_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "record_type"
      type = "string"
    }

    columns {
      name = "recorded_at"
      type = "string"
    }

    columns {
      name = "started_at"
      type = "string"
    }

    columns {
      name = "completed_at"
      type = "string"
    }

    columns {
      name = "duration_ms"
      type = "bigint"
    }

    columns {
      name = "request_id"
      type = "string"
    }

    columns {
      name = "agent_name"
      type = "string"
    }

    columns {
      name = "environment"
      type = "string"
    }

    columns {
      name = "app_id"
      type = "string"
    }

    columns {
      name = "tenant_id"
      type = "string"
    }

    columns {
      name = "session_id_requested"
      type = "string"
    }

    columns {
      name = "session_id_authorized"
      type = "string"
    }

    columns {
      name = "runtime_session_id"
      type = "string"
    }

    columns {
      name = "http_method"
      type = "string"
    }

    columns {
      name = "resource_path"
      type = "string"
    }

    columns {
      name = "source_ip"
      type = "string"
    }

    columns {
      name = "user_agent"
      type = "string"
    }

    columns {
      name = "status_code"
      type = "int"
    }

    columns {
      name = "outcome"
      type = "string"
    }

    columns {
      name = "error_message"
      type = "string"
    }

    columns {
      name = "request_prompt_chars"
      type = "int"
    }

    columns {
      name = "request_prompt_sha256"
      type = "string"
    }

    columns {
      name = "request_prompt_preview"
      type = "string"
    }

    columns {
      name = "request_prompt_preview_truncated"
      type = "boolean"
    }

    columns {
      name = "response_delta_chunks"
      type = "int"
    }

    columns {
      name = "response_bytes"
      type = "bigint"
    }

    columns {
      name = "response_sha256"
      type = "string"
    }

    columns {
      name = "response_preview"
      type = "string"
    }

    columns {
      name = "response_preview_truncated"
      type = "boolean"
    }
  }
}

resource "aws_athena_workgroup" "bff_audit_logs" {
  count = local.audit_logs_enabled ? 1 : 0
  name  = local.audit_logs_athena_workgroup

  force_destroy = false

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.logging_bucket_id}/${local.audit_logs_athena_results_prefix}"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.tags
}
