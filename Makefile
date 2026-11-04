SHELL_FILES := $(wildcard bin/* lib/*.bash test/*.bash scripts/*.bash)
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

.PHONY: help lint format test-unit canary test plugin-test

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "%-12s %s\n", $$1, $$2}'

lint: ## Run shellcheck and shfmt in check mode
	$(SHELLCHECK) -x $(SHELL_FILES)
	$(SHFMT) -d $(SHELL_FILES)

format: ## Format shell scripts with shfmt
	$(SHFMT) -w $(SHELL_FILES)

test-unit: ## Run the offline unit tests
	./test/unit.bash

canary: ## Check that the newest upstream release matches the expected layout
	./test/upstream-layout.bash

plugin-test: ## Install the plugin locally and run asdf's plugin test
	asdf plugin test openbao "$(CURDIR)" --asdf-tool-version 2.7.2 'bao --version'

test: test-unit plugin-test ## Run all tests
