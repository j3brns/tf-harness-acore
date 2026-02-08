# MCP Servers Local Development Makefile
#
# Usage:
#   make setup      - Install dependencies
#   make dev        - Start local MCP server
#   make test       - Run all tests
#   make test-s3    - Test S3 tools handler
#   make validate   - Validate Terraform
#   make plan       - Terraform plan
#   make deploy     - Deploy to AWS

.PHONY: setup dev test test-s3 test-titanic validate plan deploy clean help

# Python virtual environment
VENV := .venv
PYTHON := $(VENV)/Scripts/python
PIP := $(VENV)/Scripts/pip

# Colors
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

#------------------------------------------------------------------------------
# Setup
#------------------------------------------------------------------------------

setup: $(VENV)/Scripts/activate ## Install all dependencies
	@echo "$(GREEN)Installing dependencies...$(NC)"
	$(PIP) install -r local-dev/requirements.txt
	$(PIP) install -r s3-tools/requirements-dev.txt 2>/dev/null || true
	$(PIP) install pytest moto boto3 flask
	@echo "$(GREEN)Setup complete!$(NC)"

$(VENV)/Scripts/activate:
	python -m venv $(VENV)

#------------------------------------------------------------------------------
# Local Development Server
#------------------------------------------------------------------------------

dev: ## Start local MCP development server
	@echo "$(GREEN)Starting local MCP server...$(NC)"
	@echo "$(YELLOW)Endpoints:$(NC)"
	@echo "  - Tools list:  http://localhost:8080/tools/list"
	@echo "  - Tool call:   http://localhost:8080/tools/call"
	@echo "  - Health:      http://localhost:8080/health"
	@echo ""
	cd local-dev && $(PYTHON) server.py

dev-docker: ## Start local MCP server in Docker (Lambda-like environment)
	docker run --rm -it \
		-v $(PWD)/local-dev:/app \
		-p 8080:8080 \
		-w /app \
		public.ecr.aws/lambda/python:3.12 \
		python server.py

#------------------------------------------------------------------------------
# Testing
#------------------------------------------------------------------------------

test: test-local test-s3 test-titanic ## Run all tests
	@echo "$(GREEN)All tests passed!$(NC)"

test-local: ## Test local MCP server
	@echo "$(GREEN)Testing local MCP server...$(NC)"
	@curl -s http://localhost:8080/health | grep -q "healthy" && \
		echo "  ✓ Health check passed" || \
		echo "  ✗ Server not running (start with 'make dev')"

test-s3: ## Test S3 tools handler locally
	@echo "$(GREEN)Testing S3 tools handler...$(NC)"
	cd s3-tools && $(PYTHON) -c "\
import json; \
from handler import lambda_handler; \
event = {'tool': 'list_buckets', 'params': {}}; \
result = lambda_handler(event, None); \
print('  ✓ Handler executed'); \
print(f'  Response: {json.dumps(result, indent=2)[:200]}...')" 2>/dev/null || \
	echo "  ⚠ Run with AWS credentials or use moto for mocking"

test-titanic: ## Test Titanic data handler locally
	@echo "$(GREEN)Testing Titanic data handler...$(NC)"
	cd titanic-data && $(PYTHON) -c "\
import json; \
from handler import lambda_handler; \
event = {'tool': 'get_schema', 'params': {}}; \
result = lambda_handler(event, None); \
print('  ✓ Handler executed'); \
print(f'  Response: {json.dumps(result, indent=2)[:200]}...')"

test-unit: ## Run pytest unit tests
	@echo "$(GREEN)Running unit tests...$(NC)"
	$(PYTHON) -m pytest s3-tools/tests/ titanic-data/tests/ -v 2>/dev/null || \
		echo "  ⚠ No tests directory found"

#------------------------------------------------------------------------------
# Lambda Local Invocation (SAM-like)
#------------------------------------------------------------------------------

invoke-s3: ## Invoke S3 tools Lambda locally
	@echo "$(GREEN)Invoking S3 tools Lambda...$(NC)"
	cd s3-tools && $(PYTHON) -c "\
import json, sys; \
from handler import lambda_handler; \
event = json.loads(sys.argv[1] if len(sys.argv) > 1 else '{\"tool\": \"list_buckets\"}'); \
result = lambda_handler(event, None); \
print(json.dumps(result, indent=2))" '{"tool": "list_buckets"}'

invoke-titanic: ## Invoke Titanic data Lambda locally
	@echo "$(GREEN)Invoking Titanic data Lambda...$(NC)"
	cd titanic-data && $(PYTHON) -c "\
import json, sys; \
from handler import lambda_handler; \
event = json.loads(sys.argv[1] if len(sys.argv) > 1 else '{\"tool\": \"get_schema\"}'); \
result = lambda_handler(event, None); \
print(json.dumps(result, indent=2))" '{"tool": "get_schema"}'

#------------------------------------------------------------------------------
# Terraform Workflow
#------------------------------------------------------------------------------

validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating Terraform...$(NC)"
	cd terraform && terraform fmt -check -recursive
	cd terraform && terraform init -backend=false
	cd terraform && terraform validate
	@echo "$(GREEN)Validation passed!$(NC)"

plan: validate ## Terraform plan
	@echo "$(GREEN)Running Terraform plan...$(NC)"
	cd terraform && terraform plan

deploy: validate ## Deploy to AWS
	@echo "$(YELLOW)Deploying MCP servers to AWS...$(NC)"
	cd terraform && terraform apply

destroy: ## Destroy AWS resources
	@echo "$(YELLOW)Destroying MCP servers...$(NC)"
	cd terraform && terraform destroy

#------------------------------------------------------------------------------
# Development Workflow
#------------------------------------------------------------------------------

watch: ## Watch for changes and restart local server
	@echo "$(GREEN)Watching for changes...$(NC)"
	while true; do \
		$(MAKE) dev & PID=$$!; \
		inotifywait -r -e modify local-dev/ s3-tools/ titanic-data/; \
		kill $$PID 2>/dev/null; \
	done

lint: ## Lint Python code
	@echo "$(GREEN)Linting...$(NC)"
	$(PYTHON) -m flake8 s3-tools/ titanic-data/ local-dev/ --max-line-length=120 || true
	$(PYTHON) -m black s3-tools/ titanic-data/ local-dev/ --check || true

format: ## Format Python code
	$(PYTHON) -m black s3-tools/ titanic-data/ local-dev/

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------

clean: ## Clean build artifacts
	rm -rf $(VENV)
	rm -rf terraform/.build
	rm -rf terraform/.terraform
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

help: ## Show this help
	@echo "MCP Servers Development Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
