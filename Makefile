.PHONY: help init plan apply destroy validate fmt lint docs clean test preflight-session worktree push-main-both push-tag-both ci-status-both streaming-load-test policy-report

# Variables
ROOT_DIR := $(abspath .)
TERRAFORM_DIR := $(ROOT_DIR)/terraform
TF_FILES := $(TERRAFORM_DIR)/**/*.tf
MODULES := agentcore-foundation agentcore-tools agentcore-runtime agentcore-governance

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

init: ## Initialize Terraform (legacy, may fail if partial backend configured)
	terraform -chdir=$(TERRAFORM_DIR) init

init-segmented: ## Initialize with segmented key (provide ENV, APP_ID, AGENT_NAME, BUCKET_ID)
	@test -n "$(ENV)" || { echo "ERROR: Provide ENV (e.g., dev)"; exit 1; }
	@test -n "$(APP_ID)" || { echo "ERROR: Provide APP_ID"; exit 1; }
	@test -n "$(AGENT_NAME)" || { echo "ERROR: Provide AGENT_NAME"; exit 1; }
	@test -n "$(BUCKET_ID)" || { echo "ERROR: Provide BUCKET_ID (AWS account or suffix)"; exit 1; }
	terraform -chdir=$(TERRAFORM_DIR) init \
		-backend-config="bucket=terraform-state-$(ENV)-$(BUCKET_ID)" \
		-backend-config="key=state/$(APP_ID)/$(AGENT_NAME)/terraform.tfstate" \
		-backend-config="region=eu-west-2" \
		-backend-config="encrypt=true" \
		-backend-config="use_lockfile=true"

fmt: ## Format Terraform files
	terraform -chdir=$(TERRAFORM_DIR) fmt -recursive

validate: ## Validate Terraform configuration
	terraform -chdir=$(TERRAFORM_DIR) validate
	@echo "✓ Terraform configuration is valid"

plan: ## Create Terraform plan
	terraform -chdir=$(TERRAFORM_DIR) plan -out=$(TERRAFORM_DIR)/tfplan

plan-destroy: ## Create plan for destroying all resources
	terraform -chdir=$(TERRAFORM_DIR) plan -destroy -out=$(TERRAFORM_DIR)/tfplan

apply: ## Apply Terraform changes
	@echo "Applying Terraform changes..."
	terraform -chdir=$(TERRAFORM_DIR) apply $(TERRAFORM_DIR)/tfplan

apply-no-verify: ## Apply without plan verification
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve

destroy: ## Destroy all Terraform resources
	@echo "WARNING: This will destroy all resources. Type 'yes' to confirm."
	terraform -chdir=$(TERRAFORM_DIR) destroy

# Environment-specific targets
plan-dev:
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-dev

apply-dev: plan-dev
	terraform -chdir=$(TERRAFORM_DIR) apply $(TERRAFORM_DIR)/tfplan-dev

plan-hello-world: ## Plan hello-world example
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-hello

plan-gateway-tool: ## Plan gateway-tool example
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/2-gateway-tool/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-gateway

plan-deepresearch: ## Plan deepresearch example
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/3-deepresearch/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-deepresearch

plan-research: ## Plan simple research example
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/4-research/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-research

# Output targets
output: ## Show Terraform outputs
	terraform -chdir=$(TERRAFORM_DIR) output

output-json: ## Show outputs as JSON
	terraform -chdir=$(TERRAFORM_DIR) output -json

# State management
state-list: ## List resources in state
	terraform -chdir=$(TERRAFORM_DIR) state list

state-show: ## Show resource details (specify RESOURCE=...)
	terraform -chdir=$(TERRAFORM_DIR) state show $(RESOURCE)

state-backup: ## Create backup of Terraform state
	mkdir -p backups
	cp $(TERRAFORM_DIR)/terraform.tfstate backups/terraform.tfstate.backup-$(shell date +%s)

# Validation and security scanning
security-scan: ## Run Checkov security scan
	checkov -d $(TERRAFORM_DIR) --framework terraform --config-file $(TERRAFORM_DIR)/.checkov.yaml

tflint: ## Run TFLint for style checking
	tflint --chdir=$(TERRAFORM_DIR) --init
	tflint --chdir=$(TERRAFORM_DIR) --format compact --config $(TERRAFORM_DIR)/.tflint.hcl

# Documentation
docs: generate-openapi generate-openapi-client ## Generate all documentation (Terraform + OpenAPI + TS client)
	@echo "Generating Terraform documentation..."
	terraform-docs markdown $(TERRAFORM_DIR) > docs/terraform.md
	@echo "✓ Documentation generated to docs/terraform.md"

generate-openapi: ## Generate OpenAPI spec from MCP tools registry
	@echo "Generating OpenAPI spec..."
	python3 terraform/scripts/generate_mcp_openapi.py
	@echo "✓ OpenAPI spec generated to docs/api/mcp-tools-v1.openapi.json"

generate-openapi-client: ## Generate typed TypeScript client from MCP Tools OpenAPI spec
	@echo "Generating typed MCP Tools TypeScript client..."
	python3 terraform/scripts/generate_mcp_typescript_client.py
	@echo "✓ Typed client generated to docs/api/mcp-tools-v1.client.ts"

check-openapi-client: ## Verify generated MCP Tools TypeScript client matches OpenAPI spec
	@echo "Checking MCP Tools TypeScript client drift..."
	python3 terraform/scripts/generate_mcp_typescript_client.py --check
	@echo "✓ MCP Tools TypeScript client is in sync"

# Module management
module-list: ## List all modules
docs: generate-openapi generate-openapi-client ## Generate all documentation (Terraform + OpenAPI + TS client)
	@echo "Generating Terraform documentation..."
	terraform-docs markdown $(TERRAFORM_DIR) > docs/terraform.md
	@echo "✓ Documentation generated to docs/terraform.md"

generate-openapi: ## Generate OpenAPI spec from MCP tools registry
	@echo "Generating OpenAPI spec..."
	python3 terraform/scripts/generate_mcp_openapi.py
	@echo "✓ OpenAPI spec generated to docs/api/mcp-tools-v1.openapi.json"

generate-openapi-client: ## Generate typed TypeScript client from MCP Tools OpenAPI spec
	@echo "Generating typed MCP Tools TypeScript client..."
	python3 terraform/scripts/generate_mcp_typescript_client.py
	@echo "✓ Typed client generated to docs/api/mcp-tools-v1.client.ts"

check-openapi-client: ## Verify generated MCP Tools TypeScript client matches OpenAPI spec
	@echo "Checking MCP Tools TypeScript client drift..."
	python3 terraform/scripts/generate_mcp_typescript_client.py --check
	@echo "✓ MCP Tools TypeScript client is in sync"

openapi-contract-diff: ## Generate OpenAPI contract diff/changelog summary (OLD=path [NEW=path] [FORMAT=markdown|json] [FAIL_ON_BREAKING=1])
	@test -n "$(OLD)" || { echo "ERROR: Usage: make openapi-contract-diff OLD=<baseline-openapi.json> [NEW=docs/api/mcp-tools-v1.openapi.json]"; exit 1; }
	python3 terraform/scripts/openapi_contract_diff.py \
		--old "$(OLD)" \
		--new "$(if $(NEW),$(NEW),docs/api/mcp-tools-v1.openapi.json)" \
		--format "$(if $(FORMAT),$(FORMAT),markdown)" \
		$(if $(FAIL_ON_BREAKING),--fail-on-breaking,)

# Module management
module-list: ## List all modules
	@echo "AgentCore Modules:"
	@for module in $(MODULES); do \
		echo "  - terraform/modules/$$module"; \
		echo "    Resources:"; \
		grep -r "^resource " $(TERRAFORM_DIR)/modules/$$module/*.tf 2>/dev/null | sed 's/.* "/      /' | sort | uniq; \
	done

module-validate: ## Validate all modules
	@echo "Validating modules..."
	@for module in $(MODULES); do \
		echo "  Validating $$module..."; \
		terraform -chdir=$(TERRAFORM_DIR)/modules/$$module validate && echo "    ✓ Valid"; \
	done

# Testing - Terraform
test: test-validate test-security test-examples test-cedar test-frontend
	@echo "✓ All Terraform and Frontend tests passed"

test-validate: ## Run Terraform validation tests
	terraform -chdir=$(TERRAFORM_DIR) fmt -check -recursive
	terraform -chdir=$(TERRAFORM_DIR) validate
	@echo "✓ Terraform validation passed"

test-security: ## Run security scans
	checkov -d $(TERRAFORM_DIR) --framework terraform --compact --config-file $(TERRAFORM_DIR)/.checkov.yaml
	@echo "✓ Security scan passed"

test-examples: ## Validate all example configurations
	bash $(TERRAFORM_DIR)/scripts/validate_examples.sh
	@echo "✓ All examples validated"

test-cedar: ## Validate Cedar policies
	bash $(TERRAFORM_DIR)/scripts/validate_cedar_policies.sh
	@echo "✓ Cedar policies validated"

test-frontend: ## Run frontend accessibility regression tests
	@echo "Running frontend accessibility tests..."
	cd terraform/tests/frontend && npm install && npx playwright install chromium && npm run test:accessibility

preview-frontend: ## Run a local server to preview frontend components
	@echo "Starting component preview server on http://localhost:8080..."
	cd terraform/tests/frontend && npm install && npx http-server ./preview -p 8080 -o

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

streaming-load-test: ## Run BFF/AgentCore streaming load tester (pass ARGS='...')
	python3 terraform/scripts/streaming_load_tester.py $(ARGS)

policy-report: ## Generate policy and tag conformance report
	@echo "Generating policy and tag conformance report..."
	python3 terraform/scripts/generate_policy_conformance_report.py
	@echo "✓ Report generated to docs/POLICY_CONFORMANCE_REPORT.md"

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
	rm -rf $(TERRAFORM_DIR)/.terraform
	rm -f $(TERRAFORM_DIR)/tfplan $(TERRAFORM_DIR)/tfplan-*
	rm -f $(TERRAFORM_DIR)/terraform.tfstate*
	rm -rf backups

clean-outputs: ## Clean generated CLI output files
	find $(TERRAFORM_DIR)/modules -name ".terraform" -type d -exec rm -rf {} +
	find $(TERRAFORM_DIR)/modules -name "*.json" -path "*/.terraform/*" -delete
	find $(TERRAFORM_DIR)/modules -name "*.txt" -path "*/.terraform/*" -delete

# Development helpers
preflight-session: ## Run startup preflight checks (worktree/branch/issue policy)
	bash $(TERRAFORM_DIR)/scripts/session/preflight_startup.sh

worktree: ## Interactive menu for linked worktree create/resume + preflight
	bash $(TERRAFORM_DIR)/scripts/session/worktree.sh

format-check: ## Check if files are properly formatted
	terraform -chdir=$(TERRAFORM_DIR) fmt -check -recursive

update-providers: ## Update provider versions
	terraform -chdir=$(TERRAFORM_DIR) init -upgrade

debug: ## Enable debug logging
	export TF_LOG=DEBUG
	terraform -chdir=$(TERRAFORM_DIR) plan

# Quick start
quickstart: init validate
	@echo "✓ Terraform initialized and validated"
	@echo "Next steps:"
	@echo "  1. Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars"
	@echo "  2. Edit terraform/terraform.tfvars with your configuration"
	@echo "  3. Run 'make plan' to review changes"
	@echo "  4. Run 'make apply' to deploy"

# CI/CD helpers
ci-validate: validate fmt module-validate
	@echo "✓ CI validation passed"

ci-plan: ci-validate plan
	@echo "✓ CI plan generated"

# Dual-remote integration (GitHub + GitLab)
push-main-both: ## Push main to both origin (GitHub) and gitlab remotes
	git push origin main
	git push gitlab main

push-tag-both: ## Push TAG=vX.Y.Z to both origin and gitlab remotes
	@test -n "$(TAG)" || (echo "ERROR: Provide TAG, e.g. make push-tag-both TAG=v0.1.0" && exit 1)
	git push origin $(TAG)
	git push gitlab $(TAG)

ci-status-both: ## Show recent GitHub Actions and current GitLab CI status
	@echo "GitHub Actions (latest 5):"
	gh run list --limit 5 || true
	@echo ""
	@echo "GitLab CI status:"
	glab ci status || true

.DEFAULT_GOAL := help
