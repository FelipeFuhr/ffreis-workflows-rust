.DEFAULT_GOAL := help

.PHONY: help lint test check fmt-check secrets-scan-staged lefthook-bootstrap lefthook-install hooks setup

## help: Show this help message
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed 's/## //'

## lint: Validate workflow YAML + clippy on examples/hello
lint:
	@echo "==> Linting GitHub Actions workflow files..."
	@if command -v actionlint >/dev/null 2>&1; then \
		actionlint .github/workflows/*.yml; \
	else \
		echo "actionlint not found; falling back to yamllint..."; \
		if command -v yamllint >/dev/null 2>&1; then \
			yamllint -d relaxed .github/workflows/*.yml; \
		else \
			echo "Neither actionlint nor yamllint found. Install one to lint workflows."; \
			exit 1; \
		fi \
	fi
	@for ex in examples/*/; do \
		echo "==> clippy $$ex"; \
		( cd "$$ex" && cargo clippy --all-targets --all-features -- -D warnings ) || exit 1; \
	done

## fmt-check: Check Rust example formatting
fmt-check:
	@for ex in examples/*/; do \
		echo "==> fmt-check $$ex"; \
		( cd "$$ex" && cargo fmt --all -- --check ) || exit 1; \
	done

## test: Run the bats suites under tests/
test:
	@command -v bats >/dev/null 2>&1 || { \
		echo "ERROR: bats not found. Install it from https://github.com/bats-core/bats-core"; \
		exit 1; \
	}
	@echo "==> Running bats suites..."
	@bats tests/

## check: Run all local checks (lint + test)
check: lint test
	@echo "==> All checks passed."

## secrets-scan-staged: Scan staged files for secrets
secrets-scan-staged:
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo "ERROR: gitleaks not found. Install it from https://github.com/gitleaks/gitleaks#installing"; \
		echo "Tip: run 'make setup' after installing to verify your dev environment."; \
		exit 1; \
	}
	gitleaks protect --staged --redact

## lefthook-bootstrap: Download lefthook binary to .bin/
lefthook-bootstrap:
	LEFTHOOK_VERSION="1.7.10" BIN_DIR=".bin" bash ./scripts/bootstrap_lefthook.sh

## lefthook-install: Install git hooks via lefthook
lefthook-install:
	./.bin/lefthook install

## hooks: Bootstrap and install all git hooks
hooks: lefthook-bootstrap lefthook-install

## setup: Install git hooks and verify required tools
setup: hooks
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo ""; \
		echo "ACTION REQUIRED: gitleaks is not installed."; \
		echo "Install it from https://github.com/gitleaks/gitleaks#installing then re-run 'make setup'."; \
		echo ""; \
		exit 1; \
	}
	@echo "Dev environment ready."

PLATFORM_STANDARDS_SHA ?= 3c787edb4e96ddea2e86b2add2c32139685e8db7  # v1.2.1
PLATFORM_STANDARDS_RAW ?= https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-standards

install-act: ## Download pinned act binary into .bin/
	@mkdir -p scripts
	@curl -fsSL "$(PLATFORM_STANDARDS_RAW)/$(PLATFORM_STANDARDS_SHA)/scripts/install_act.sh" \
		-o scripts/install_act.sh && chmod +x scripts/install_act.sh
	@bash ./scripts/install_act.sh

ci-local: ## Run workflows locally via act (GH Actions quota fallback). Args via ARGS=...
	@mkdir -p scripts
	@curl -fsSL "https://raw.githubusercontent.com/FelipeFuhr/ffreis-platform-ci-local/v1.0.0/scripts/run-ci-local.sh" \
		-o scripts/run-ci-local.sh && chmod +x scripts/run-ci-local.sh
	@CI_LOCAL_FINDINGS_REF=v1.0.0 PATH="$(CURDIR)/.bin:$(PATH)" bash ./scripts/run-ci-local.sh $(ARGS)
