terraform {
  required_version = ">= 1.10.0" # Required for native S3 state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.33.0" # Freeze Point for Workstream A (Novation Matrix, Issue #17)
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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = local.agentcore_region

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "BedrockAgentCore"
      # Canonical tag taxonomy (Issue #22) - applied to all AWS resources automatically.
      AppID     = var.app_id != "" ? var.app_id : var.agent_name
      AgentName = var.agent_name
      ManagedBy = "terraform"
      Owner     = var.owner != "" ? var.owner : (var.app_id != "" ? var.app_id : var.agent_name)
    }
  }
}

provider "aws" {
  alias  = "bff"
  region = local.bff_region

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "BedrockAgentCore"
      # Canonical tag taxonomy (Issue #22) - applied to all AWS resources automatically.
      AppID     = var.app_id != "" ? var.app_id : var.agent_name
      AgentName = var.agent_name
      ManagedBy = "terraform"
      Owner     = var.owner != "" ? var.owner : (var.app_id != "" ? var.app_id : var.agent_name)
    }
  }
}
