# Developer entrypoints. `make help` lists targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help

PY      ?= python3
VENV    ?= .venv
BIN     := $(VENV)/bin
IMAGE   ?= mission-api:local
TF_DIRS := terraform/environments/dev terraform/bootstrap

.PHONY: help venv install lint test sast run up down token call call-guest \
        build trivy tf-fmt tf-validate tflint checkov gitleaks scan k8s-render ci clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

venv: ## Create virtualenv
	$(PY) -m venv $(VENV)

install: venv ## Install app + dev dependencies
	$(BIN)/pip install -q -r app/requirements-dev.txt

lint: ## Ruff lint
	$(BIN)/ruff check app

test: ## Unit tests with coverage
	$(BIN)/pytest --cov=app --cov-report=term-missing --cov-fail-under=85

sast: ## Bandit SAST
	$(BIN)/bandit -c pyproject.toml -r app --severity-level medium

run: ## Run the API locally (no container)
	OIDC_ISSUER=http://localhost:8080/realms/devsecops $(BIN)/uvicorn app.main:app --reload --port 8000

up: ## Start API + Keycloak with docker compose
	docker compose up --build -d
	@echo "API: http://localhost:8000/docs   Keycloak: http://localhost:8080 (admin/admin)"

down: ## Stop the compose stack
	docker compose down -v

token: ## Print an access token for analyst1 (has mission-reader)
	@scripts/get-token.sh

call: ## Call the protected endpoint as analyst1 (expect 200)
	curl -s -H "Authorization: Bearer $$(scripts/get-token.sh)" http://localhost:8000/api/v1/mission; echo

call-guest: ## Call as guest1 (no role, expect 403)
	curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $$(scripts/get-token.sh guest1 'Guest#Demo2026')" http://localhost:8000/api/v1/mission

build: ## Build the container image
	docker build -t $(IMAGE) .

trivy: build ## Scan the image (fail on fixable HIGH/CRITICAL)
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

tf-fmt: ## terraform fmt check
	terraform fmt -recursive -check -diff terraform

tf-validate: ## terraform init (no backend) + validate
	@for d in $(TF_DIRS); do echo "== $$d"; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; done

tflint: ## TFLint (recursive, AWS ruleset)
	cd terraform && tflint --init --config=$$PWD/.tflint.hcl && tflint --recursive --config=$$PWD/.tflint.hcl --format=compact

checkov: ## Checkov: Terraform, K8s, Dockerfile, GitHub Actions, secrets
	checkov -d . --config-file .checkov.yaml

gitleaks: ## Secret scan of git history
	gitleaks git --config .gitleaks.toml --redact -v .

k8s-render: ## Render kustomize overlays
	@for e in dev stage prod; do kubectl kustomize k8s/overlays/$$e > /dev/null && echo "rendered $$e"; done

scan: sast tf-fmt tf-validate tflint checkov gitleaks ## All security/IaC scans

ci: lint test scan ## Everything CI runs that works offline

clean: ## Remove caches
	rm -rf .pytest_cache .ruff_cache .coverage coverage.xml $(VENV) **/__pycache__
	find terraform -name .terraform -type d -prune -exec rm -rf {} +
