.DEFAULT_GOAL := help

.PHONY: help lint check fmt-check secrets-scan-staged lefthook-bootstrap lefthook-install hooks

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
	cd examples/hello && cargo clippy --all-targets --all-features -- -D warnings

## fmt-check: Check Rust example formatting
fmt-check:
	cd examples/hello && cargo fmt --all -- --check

## check: Run all local checks (lint)
check: lint
	@echo "==> All checks passed."

## secrets-scan-staged: Scan staged files for secrets
secrets-scan-staged:
	gitleaks protect --staged --redact

## lefthook-bootstrap: Download lefthook binary to .bin/
lefthook-bootstrap:
	LEFTHOOK_VERSION="1.7.10" BIN_DIR=".bin" bash ./scripts/bootstrap_lefthook.sh

## lefthook-install: Install git hooks via lefthook
lefthook-install:
	./.bin/lefthook install

## hooks: Bootstrap and install all git hooks
hooks: lefthook-bootstrap lefthook-install
