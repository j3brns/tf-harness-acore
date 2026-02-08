.PHONY: help init plan apply destroy validate fmt lint docs clean test

# Variables
TERRAFORM_DIR = .
TF_FILES = $(TERRAFORM_DIR)/**/*.tf
MODULES = agentcore-foundation agentcore-tools agentcore-runtime agentcore-governance

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform init

fmt: ## Format Terraform files
	terraform fmt -recursive

validate: ## Validate Terraform configuration
	terraform validate
	@echo "✓ Terraform configuration is valid"

plan: ## Create Terraform plan
	terraform plan -out=tfplan

plan-destroy: ## Create plan for destroying all resources
	terraform plan -destroy -out=tfplan

apply: ## Apply Terraform changes
	@echo "Applying Terraform changes..."
	terraform apply tfplan

apply-no-verify: ## Apply without plan verification
	terraform apply -auto-approve

destroy: ## Destroy all Terraform resources
	@echo "WARNING: This will destroy all resources. Type 'yes' to confirm."
	terraform destroy

# Environment-specific targets
plan-dev:
	terraform plan -var-file="examples/1-hello-world/terraform.tfvars" -out=tfplan-dev

apply-dev: plan-dev
	terraform apply tfplan-dev

plan-hello-world: ## Plan hello-world example
	terraform plan -var-file="examples/1-hello-world/terraform.tfvars" -out=tfplan-hello

plan-gateway-tool: ## Plan gateway-tool example
	terraform plan -var-file="examples/2-gateway-tool/terraform.tfvars" -out=tfplan-gateway

plan-deepresearch: ## Plan deepresearch example
	terraform plan -var-file="examples/3-deepresearch/terraform.tfvars" -out=tfplan-deepresearch

plan-research: ## Plan simple research example
	terraform plan -var-file="examples/4-research/terraform.tfvars" -out=tfplan-research

# Output targets
output: ## Show Terraform outputs
	terraform output

output-json: ## Show outputs as JSON
	terraform output -json

# State management
state-list: ## List resources in state
	terraform state list

state-show: ## Show resource details (specify RESOURCE=...)
	terraform state show $(RESOURCE)

state-backup: ## Create backup of Terraform state
	mkdir -p backups
	cp terraform.tfstate backups/terraform.tfstate.backup-$(shell date +%s)

# Validation and security scanning
security-scan: ## Run Checkov security scan
	checkov -d . --framework terraform

tflint: ## Run TFLint for style checking
	tflint --init
	tflint

# Documentation
docs: ## Generate Terraform documentation
	@echo "Generating documentation..."
	terraform-docs markdown . > docs/terraform.md
	@echo "✓ Documentation generated to docs/terraform.md"

# Module management
module-list: ## List all modules
	@echo "AgentCore Modules:"
	@for module in $(MODULES); do \
		echo "  - modules/$$module"; \
		echo "    Resources:"; \
		grep -r "^resource " modules/$$module/*.tf 2>/dev/null | sed 's/.* "/      /' | sort | uniq; \
	done

module-validate: ## Validate all modules
	@echo "Validating modules..."
	@for module in $(MODULES); do \
		echo "  Validating $$module..."; \
		cd modules/$$module && terraform validate && cd ../../ && echo "    ✓ Valid"; \
	done

# Testing - Terraform
test: test-validate test-security test-examples test-cedar
	@echo "✓ All Terraform tests passed"

test-validate: ## Run Terraform validation tests
	terraform fmt -check -recursive
	terraform validate
	@echo "✓ Terraform validation passed"

test-security: ## Run security scans
	checkov -d . --framework terraform --compact --config-file .checkov.yaml
	@echo "✓ Security scan passed"

test-examples: ## Validate all example configurations
	bash scripts/validate_examples.sh
	@echo "✓ All examples validated"

test-cedar: ## Validate Cedar policies
	bash scripts/validate_cedar_policies.sh
	@echo "✓ Cedar policies validated"

# Testing - Python (All example agents)
test-python: test-python-hello test-python-gateway test-python-deepresearch test-python-research ## Run all Python tests
	@echo "✓ All Python tests passed"

test-python-hello: ## Run hello-world agent tests
	cd examples/1-hello-world/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --tb=short

test-python-gateway: ## Run gateway-tool agent tests
	cd examples/2-gateway-tool/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --tb=short

test-python-deepresearch: ## Run deepresearch agent tests
	cd examples/3-deepresearch/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --tb=short

test-python-research: ## Run simple research agent tests
	cd examples/4-research/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --tb=short

test-python-unit: ## Run all Python unit tests
	@for example in 1-hello-world 2-gateway-tool 4-research; do \
		echo "Testing $$example..."; \
		cd examples/$$example/agent-code && pip install -q -e ".[dev]" && python -m pytest tests/ -v --tb=short && cd ../../../; \
	done
	cd examples/3-deepresearch/agent-code && pip install -q -e ".[dev]" && python -m pytest tests/unit -v --tb=short

test-python-integration: ## Run Python integration tests
	cd examples/3-deepresearch/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/integration -v --tb=short

test-python-coverage: ## Run Python tests with coverage
	cd examples/3-deepresearch/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --cov=deepresearch --cov-report=term-missing --cov-report=html

test-all: test test-python ## Run all tests (Terraform + Python)
	@echo "✓ All tests passed"

# Logging and monitoring
logs-gateway: ## Tail gateway logs
	aws logs tail /aws/bedrock/agentcore/gateway/$(AGENT_NAME) --follow

logs-runtime: ## Tail runtime logs
	aws logs tail /aws/bedrock/agentcore/runtime/$(AGENT_NAME) --follow

logs-code-interpreter: ## Tail code interpreter logs
	aws logs tail /aws/bedrock/agentcore/code-interpreter/$(AGENT_NAME) --follow

logs-browser: ## Tail browser logs
	aws logs tail /aws/bedrock/agentcore/browser/$(AGENT_NAME) --follow

logs-policy: ## Tail policy engine logs
	aws logs tail /aws/bedrock/agentcore/policy-engine/$(AGENT_NAME) --follow

logs-evaluator: ## Tail evaluator logs
	aws logs tail /aws/bedrock/agentcore/evaluator/$(AGENT_NAME) --follow

# Cleanup
clean: ## Clean Terraform cache and temporary files
	rm -rf .terraform
	rm -f tfplan tfplan-*
	rm -f terraform.tfstate*
	rm -rf backups

clean-outputs: ## Clean generated CLI output files
	find modules -name ".terraform" -type d -exec rm -rf {} +
	find modules -name "*.json" -path "*/.terraform/*" -delete
	find modules -name "*.txt" -path "*/.terraform/*" -delete

# Development helpers
format-check: ## Check if files are properly formatted
	terraform fmt -check -recursive

update-providers: ## Update provider versions
	terraform init -upgrade

debug: ## Enable debug logging
	export TF_LOG=DEBUG
	terraform plan

# Quick start
quickstart: init validate
	@echo "✓ Terraform initialized and validated"
	@echo "Next steps:"
	@echo "  1. Copy terraform.tfvars.example to terraform.tfvars"
	@echo "  2. Edit terraform.tfvars with your configuration"
	@echo "  3. Run 'make plan' to review changes"
	@echo "  4. Run 'make apply' to deploy"

# CI/CD helpers
ci-validate: validate fmt module-validate
	@echo "✓ CI validation passed"

ci-plan: ci-validate plan
	@echo "✓ CI plan generated"

.DEFAULT_GOAL := help
