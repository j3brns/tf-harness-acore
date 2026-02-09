terraform {
  required_version = ">= 1.10.0" # Required for native S3 state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80" # Updated Feb 2025 - allows 5.80.x through 5.x
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "BedrockAgentCore"
      # Note: Removed timestamp() as it causes non-idempotent plans
      # Use lifecycle ignore_changes or external tagging if needed
    }
  }
}
