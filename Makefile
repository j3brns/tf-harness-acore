.PHONY: help init plan apply destroy validate fmt lint docs clean test preflight-session pre-validate-session validate-ci-fast validate-ci-full worktree issue-queue worktree-next-issue worktree-create-issue worktree-resume-issue worktree-push-issue terraform-init-local terraform-validate-local terraform-plan-local validate-fast validate-scope validate-push finish-worktree-summary finish-worktree-close toolchain-versions push-main-both push-tag-both push-checkpoint-tag-both ci-status-both streaming-load-test policy-report validate-region validate-version-metadata validate-sdk-compat-matrix validate-deps

# Variables
ROOT_DIR := $(abspath .)
TERRAFORM_DIR := $(ROOT_DIR)/terraform
TF_FILES := $(TERRAFORM_DIR)/**/*.tf
MODULES := agentcore-foundation agentcore-tools agentcore-runtime agentcore-governance
DEFAULT_TFVARS := $(ROOT_DIR)/examples/1-hello-world/terraform.tfvars
LOCAL_TF_DATA_DIR := $(ROOT_DIR)/.scratch/tf-data
LOCAL_TF_PLUGIN_CACHE_DIR := $(ROOT_DIR)/.scratch/tf-plugin-cache

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform -chdir=$(TERRAFORM_DIR) init

fmt: ## Format Terraform files
	terraform -chdir=$(TERRAFORM_DIR) fmt -recursive

validate: ## Validate Terraform configuration
	terraform -chdir=$(TERRAFORM_DIR) validate
	@echo "✓ Terraform configuration is valid"

plan: ## Create Terraform plan
	$(MAKE) validate-region
	terraform -chdir=$(TERRAFORM_DIR) plan -out=$(TERRAFORM_DIR)/tfplan

plan-destroy: ## Create plan for destroying all resources
	terraform -chdir=$(TERRAFORM_DIR) plan -destroy -out=$(TERRAFORM_DIR)/tfplan

apply: ## Apply Terraform changes
	@echo "Applying Terraform changes..."
	$(MAKE) validate-region
	terraform -chdir=$(TERRAFORM_DIR) apply $(TERRAFORM_DIR)/tfplan

apply-no-verify: ## Apply without plan verification
	$(MAKE) validate-region
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve

destroy: ## Destroy all Terraform resources
	@echo "WARNING: This will destroy all resources. Type 'yes' to confirm."
	terraform -chdir=$(TERRAFORM_DIR) destroy

# Environment-specific targets
plan-dev:
	$(MAKE) validate-region TFVARS="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars"
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-dev

apply-dev: plan-dev
	terraform -chdir=$(TERRAFORM_DIR) apply $(TERRAFORM_DIR)/tfplan-dev

plan-hello-world: ## Plan hello-world example
	$(MAKE) validate-region TFVARS="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars"
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/1-hello-world/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-hello

plan-gateway-tool: ## Plan gateway-tool example
	$(MAKE) validate-region TFVARS="$(ROOT_DIR)/examples/2-gateway-tool/terraform.tfvars"
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/2-gateway-tool/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-gateway

plan-deepresearch: ## Plan deepresearch example
	$(MAKE) validate-region TFVARS="$(ROOT_DIR)/examples/3-deepresearch/terraform.tfvars"
	terraform -chdir=$(TERRAFORM_DIR) plan -var-file="$(ROOT_DIR)/examples/3-deepresearch/terraform.tfvars" -out=$(TERRAFORM_DIR)/tfplan-deepresearch

plan-research: ## Plan simple research example
	$(MAKE) validate-region TFVARS="$(ROOT_DIR)/examples/4-research/terraform.tfvars"
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
docs: generate-openapi generate-openapi-client report-sdk-drift ## Generate all documentation (Terraform + OpenAPI + TS client + SDK Drift)
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

report-sdk-drift: ## Generate SDK version drift report for example agents
	@echo "Generating SDK version drift report..."
	python3 terraform/scripts/report_sdk_drift.py
	@echo "✓ SDK version drift report generated to docs/SDK_VERSION_DRIFT_REPORT.md"

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

test-frontend: ## Run frontend Playwright tests
	@echo "Running frontend Playwright tests..."
	cd terraform/tests/frontend && npm install && npx playwright install chromium && npm run test:frontend

preview-frontend: ## Run a local server to preview frontend components
	@echo "Starting component preview server on http://localhost:8080..."
	cd terraform/tests/frontend && npm install && npx http-server ./preview -p 8080 -o

# Testing - Python (All example agents with tests)
test-python: test-python-hello test-python-gateway test-python-deepresearch test-python-research test-python-langgraph ## Run all Python tests
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

test-python-langgraph: ## Run LangGraph baseline agent tests
	cd examples/6-langgraph-baseline/agent-code && \
	pip install -q -e ".[dev]" && \
	python -m pytest tests/ -v --tb=short

test-python-unit: ## Run all Python unit tests
	@for example in 1-hello-world 2-gateway-tool 4-research 6-langgraph-baseline; do \
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

validate-region: ## Validate AgentCore Runtime region deployability (TFVARS=... or REGION=/AGENTCORE_REGION=/BEDROCK_REGION=/BFF_REGION=...)
	python3 terraform/scripts/validate_agentcore_runtime_region.py \
		$(if $(TFVARS),--tfvars "$(TFVARS)",) \
		$(if $(REGION),--region "$(REGION)",) \
		$(if $(AGENTCORE_REGION),--agentcore-region "$(AGENTCORE_REGION)",) \
		$(if $(BEDROCK_REGION),--bedrock-region "$(BEDROCK_REGION)",) \
		$(if $(BFF_REGION),--bff-region "$(BFF_REGION)",)

validate-version-metadata: ## Validate VERSION, CHANGELOG.md, and docs version metadata consistency
	python3 terraform/scripts/validate_version_metadata.py

validate-sdk-compat-matrix: ## Run SDK compatibility smoke matrix for example agents (LANE=... EXAMPLE=... ARGS='...')
	python3 terraform/scripts/validate_sdk_compatibility_matrix.py \
		$(if $(LANE),--lane "$(LANE)",) \
		$(if $(EXAMPLE),--example "$(EXAMPLE)",) \
		$(if $(REUSE_VENV),--reuse-venv,) \
		$(if $(SKIP_PIP_UPGRADE),--skip-pip-upgrade,) \
		$(ARGS)

validate-deps: ## Validate SDK dependency combination compatibility (Python 3.12, issue #122)
	bash $(TERRAFORM_DIR)/scripts/validate_deps.sh

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
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh

issue-queue: ## Show ready issue queue ordered for make worktree (STREAM=<label> optional)
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh queue "$(STREAM)"

worktree-next-issue: ## Create a worktree for the next ready issue (STREAM=<label>, OPEN_SHELL=1 optional)
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh next-issue "$(STREAM)" "$(OPEN_SHELL)"

worktree-create-issue: ## Create a worktree for a specific issue (ISSUE=<num>, OPEN_SHELL=1 optional)
	@test -n "$(ISSUE)" || (echo "ERROR: ISSUE required. Usage: make worktree-create-issue ISSUE=134 [OPEN_SHELL=1]" && exit 1)
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh create-issue "$(ISSUE)" "$(OPEN_SHELL)"

worktree-resume-issue: ## Resume an issue worktree with preflight (WT_PATH=... optional, OPEN_SHELL=1 optional)
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh resume-issue "$(WT_PATH)" "$(OPEN_SHELL)"

terraform-init-local: ## Initialize Terraform locally with scratch data/plugin caches for offline-friendly validation
	mkdir -p $(LOCAL_TF_DATA_DIR) $(LOCAL_TF_PLUGIN_CACHE_DIR)
	@start=$$(date +%s); \
	echo "==> terraform init (local scratch bootstrap)"; \
	timeout 180s env TF_DATA_DIR=$(LOCAL_TF_DATA_DIR) TF_PLUGIN_CACHE_DIR=$(LOCAL_TF_PLUGIN_CACHE_DIR) terraform -chdir=$(TERRAFORM_DIR) init -backend=false -reconfigure -input=false; \
	status=$$?; \
	end=$$(date +%s); \
	echo "==> terraform init finished in $$((end - start))s (status=$$status)"; \
	if [ $$status -ne 0 ]; then \
		status=$$?; \
		echo "ERROR: local terraform init failed."; \
		echo "Hint: the first bootstrap needs network access to download providers into .scratch/tf-plugin-cache."; \
		echo "Hint: rerun 'make terraform-init-local' after verifying outbound access to registry.terraform.io and releases.hashicorp.com."; \
		exit $$status; \
	fi

terraform-validate-local: ## Run terraform validate with timing and scratch-local caches
	@start=$$(date +%s); \
	echo "==> terraform validate"; \
	timeout 300s env TF_DATA_DIR=$(LOCAL_TF_DATA_DIR) TF_PLUGIN_CACHE_DIR=$(LOCAL_TF_PLUGIN_CACHE_DIR) terraform -chdir=$(TERRAFORM_DIR) validate; \
	status=$$?; \
	end=$$(date +%s); \
	echo "==> terraform validate finished in $$((end - start))s (status=$$status)"; \
	if [ $$status -ne 0 ]; then \
		echo "ERROR: terraform validate failed or timed out."; \
		echo "Hint: rerun 'make terraform-validate-local' directly to isolate validation from the wider harness."; \
		exit $$status; \
	fi

terraform-plan-local: ## Run terraform plan -backend=false with timing and scratch-local caches (TFVARS=... optional)
	@start=$$(date +%s); \
	echo "==> terraform plan -backend=false"; \
	timeout 600s env TF_DATA_DIR=$(LOCAL_TF_DATA_DIR) TF_PLUGIN_CACHE_DIR=$(LOCAL_TF_PLUGIN_CACHE_DIR) terraform -chdir=$(TERRAFORM_DIR) plan -backend=false -lock=false -var-file="../$(patsubst $(ROOT_DIR)/%,%,$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS)))"; \
	status=$$?; \
	end=$$(date +%s); \
	echo "==> terraform plan finished in $$((end - start))s (status=$$status)"; \
	if [ $$status -ne 0 ]; then \
		echo "ERROR: terraform plan failed or timed out."; \
		echo "Hint: rerun 'make terraform-plan-local TFVARS=<path>' directly to debug the planning path."; \
		exit $$status; \
	fi

validate-fast: ## Fast inner loop: preflight + fmt/check + validate + region guard (TFVARS=... optional)
	$(MAKE) preflight-session
	$(MAKE) terraform-init-local
	terraform -chdir=$(TERRAFORM_DIR) fmt -check -recursive
	$(MAKE) terraform-validate-local
	$(MAKE) validate-region TFVARS="$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS))"

validate-scope: ## Scope validation (SCOPE=terraform|python|docs|frontend|all; TFVARS=... optional)
	@case "$(SCOPE)" in \
	  ""|terraform) \
	    $(MAKE) validate-fast TFVARS="$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS))" ;; \
	  python) \
	    $(MAKE) test-python-unit ;; \
	  docs) \
	    $(MAKE) validate-version-metadata && $(MAKE) check-openapi-client ;; \
	  frontend) \
	    $(MAKE) test-frontend ;; \
	  all) \
	    $(MAKE) validate-push TFVARS="$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS))" ;; \
	  *) \
	    echo "ERROR: unknown SCOPE='$(SCOPE)'. Use terraform, python, docs, frontend, or all."; \
	    exit 1 ;; \
	esac

validate-push: ## Pre-push gate: preflight + Terraform + plan + policy + scanners + pre-commit (TFVARS=... optional)
	$(MAKE) preflight-session
	$(MAKE) terraform-init-local
	terraform -chdir=$(TERRAFORM_DIR) fmt -check -recursive
	$(MAKE) terraform-validate-local
	$(MAKE) validate-region TFVARS="$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS))"
	$(MAKE) terraform-plan-local TFVARS="$(if $(TFVARS),$(TFVARS),$(DEFAULT_TFVARS))"
	$(MAKE) policy-report
	tflint --chdir=$(TERRAFORM_DIR) --init
	tflint --chdir=$(TERRAFORM_DIR) --recursive --config $(TERRAFORM_DIR)/.tflint.hcl
	checkov -d $(TERRAFORM_DIR) --framework terraform --compact --config-file $(TERRAFORM_DIR)/.checkov.yaml
	pre-commit run --all-files

pre-validate-session: ## Enforced pre-push validation for the current worktree
	$(MAKE) preflight-session
	$(MAKE) validate-push

validate-ci-fast: ## Local approximation of the fast GitHub validation lane
	$(MAKE) validate-version-metadata
	$(MAKE) check-openapi-client
	$(MAKE) toolchain-versions
	$(MAKE) issue-queue

validate-ci-full: ## Local approximation of the broad CI lane
	$(MAKE) validate-ci-fast
	$(MAKE) validate-push
	$(MAKE) validate-sdk-compat-matrix
	$(MAKE) validate-deps

worktree-push-issue: ## Preflight + validate + push the current issue branch
	$(MAKE) pre-validate-session
	git push -u origin $$(git branch --show-current)

finish-worktree-summary: ## Print finish-stage summary for the current worktree
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh summary-current

finish-worktree-close: ## Run guided finish protocol for the current worktree
	@bash $(TERRAFORM_DIR)/scripts/session/worktree.sh finish-current

toolchain-versions: ## Show local Terraform CLI version and repo provider/version constraints
	@echo "Terraform CLI:"
	@terraform version
	@echo ""
	@echo "Repo version constraints:"
	@rg -n "required_version|source  = \"hashicorp/|version = \"~>" $(TERRAFORM_DIR)/versions.tf $(TERRAFORM_DIR)/modules/*/versions.tf

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
	@printf '%s\n' "$(TAG)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$' || (echo "ERROR: Release TAG must match vMAJOR.MINOR.PATCH (e.g. v0.1.0)" && exit 1)
	git push origin $(TAG)
	git push gitlab $(TAG)

push-checkpoint-tag-both: ## Push TAG=checkpoint/<label> to both origin and gitlab remotes (validation only, no prod promotion semantics)
	@test -n "$(TAG)" || (echo "ERROR: Provide TAG, e.g. make push-checkpoint-tag-both TAG=checkpoint/2026-02-25-ci-checkpoint" && exit 1)
	@printf '%s\n' "$(TAG)" | grep -Eq '^checkpoint/.+$$' || (echo "ERROR: Checkpoint TAG must match checkpoint/<label>" && exit 1)
	git push origin $(TAG)
	git push gitlab $(TAG)

ci-status-both: ## Show recent GitHub Actions and current GitLab CI status
	@echo "GitHub Actions (latest 5):"
	gh run list --limit 5 || true
	@echo ""
	@echo "GitLab CI status:"
	glab ci status || true

.DEFAULT_GOAL := help
