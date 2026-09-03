# MIT License
#
# Copyright (c) 2024 Ad Noctem Collective
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


DBG_MAKEFILE ?=
ifeq ($(DBG_MAKEFILE),1)
$(warning ***** starting Makefile for goal(s) "$(MAKECMDGOALS)")
$(warning ***** $(shell date))
else
# If we're not debugging the Makefile, don't echo recipes.
MAKEFLAGS += -s
endif

# -------------------------------------
# Configuration
# -------------------------------------

SHELL := /bin/bash

export ROOT_DIR = $(shell git rev-parse --show-toplevel)
export PROJ_NAME = $(shell basename "$(ROOT_DIR)")

# ---------------------------
# Constants
# ---------------------------
VERSION := 0.1.1

# Build output
OUT_DIR := $(ROOT_DIR)/dist
SCRIPT_DIR := $(ROOT_DIR)/scripts
LIB_DIR := $(ROOT_DIR)/lib
BIN_DIR := $(ROOT_DIR)/bin
TOOLS_DIR := $(ROOT_DIR)/tools
CI_DIR := $(ROOT_DIR)/.github
CI_LINTER_DIR := $(CI_DIR)/linters
TEST_DIR := $(ROOT_DIR)/test

# Documentation
DOCS_DIR := $(ROOT_DIR)/docs
MARKDOWNLINT_CONFIG := $(CI_LINTER_DIR)/.markdown-lint.yml
GITLEAKS_CONFIG := $(CI_LINTER_DIR)/.gitleaks.toml

# ---------------------------
# Sources
# ---------------------------
# The directories that ship in a release, and therefore the ones the linters
# care about. 'bin/' holds executables without a .sh suffix, so it is matched
# by type rather than by extension.
BUNDLES := scripts lib bin tools
BIN_SOURCES := $(shell find $(BIN_DIR) -maxdepth 1 -type f ! -name '*.md' 2>/dev/null)
SHELL_SOURCES := $(wildcard $(LIB_DIR)/*.sh) $(wildcard $(SCRIPT_DIR)/*.sh) $(wildcard $(TOOLS_DIR)/*.sh) $(BIN_SOURCES)

# Prefer a bats on PATH (CI installs one) and fall back to the submodule.
BATS := $(shell command -v bats 2>/dev/null || echo $(TEST_DIR)/bats/core/bin/bats)

# Only export variables from here, so the top-level Makefile's notion of the
# source lists does not leak into the different sub-makes
export

# ---------------------------
# Executables
# ---------------------------
shellcheck := shellcheck
shfmt := shfmt
markdownlint := markdownlint
gitleaks := gitleaks
actionlint := actionlint

EXECUTABLES := $(shellcheck) $(shfmt) $(markdownlint) $(gitleaks) $(actionlint)

# ---------------------------
# User-defined variables
# ---------------------------
PRINT_HELP ?=
WHAT ?=

# ---------------------------
# Custom functions
# ---------------------------
# Logging delegates to lib/log.sh so the colours have one definition in the
# repository rather than a second copy here.

define log_info
 @. $(LIB_DIR)/log.sh && lib::log::cyan $(1)
endef

define log_success
 @. $(LIB_DIR)/log.sh && lib::log::green $(1)
endef

define log_notice
 @. $(LIB_DIR)/log.sh && lib::log::yellow $(1)
endef

define log_attention
 @. $(LIB_DIR)/log.sh && lib::log::red $(1)
endef

# ---------------------------
#   Source Targets
# ---------------------------

define ALL_INFO
# All creates all source bundles for distribution.
#
# Arguments:
#   PRINT_HELP: 'y' or 'n'
endef
.PHONY: all
ifeq ($(PRINT_HELP), y)
all:
	echo "$$ALL_INFO"
else
all: clean
	$(call log_success, "Building all bundles into $(OUT_DIR)")
	@$(MAKE) build
endif

define BUILD_INFO
# Build a source bundle for distribution.
#
# Arguments:
#   PRINT_HELP: 'y' or 'n'
#   WHAT: 'scripts', 'lib', 'bin'
endef
.PHONY: build
ifeq ($(PRINT_HELP), y)
build:
	echo "$$BUILD_INFO"
else
build: out-dir
ifeq ($(WHAT),)
	$(call log_success, "Building the complete bundle and one per directory into $(OUT_DIR)")
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-$(VERSION).tar.gz" $(BUNDLES)
	# do not remove the ending semicolon as it will break the target
	$(foreach type,$(BUNDLES),tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-$(type)-$(VERSION).tar.gz" $(type);)
else
	$(call log_success, "Building tarball bundle for $(WHAT)")
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-$(WHAT)-$(VERSION).tar.gz" $(WHAT)
endif
endif


define TEST_INFO
# Run tests for the Bash library.
#
# Arguments:
#   PRINT_HELP: 'y' or 'n'
#   WHAT: a subdirectory of test/, e.g. 'lib'
endef
.PHONY: test
ifeq ($(PRINT_HELP), y)
test:
	echo "$$TEST_INFO"
else
test: update-submodules
ifeq ($(WHAT),)
	$(call log_success, "Testing all Bash sources!")
	@$(BATS) -r $(TEST_DIR)/lib
else
	$(call log_success, "Testing Bash sources for $(WHAT)")
	@$(BATS) -r $(TEST_DIR)/$(WHAT)
endif
endif

# ---------------------------
#   Housekeeping
# ---------------------------

.PHONY: init
init: update-submodules
	$(call log_success, "$(PROJ_NAME) is ready for development!")

.PHONY: update-submodules
update-submodules:
	$(call log_notice, "Updating BATS submodules for $(PROJ_NAME) at: $(TEST_DIR)")
	git submodule update --init --force

.PHONY: clean
clean:
	$(call log_attention, "Removing output directory for $(PROJ_NAME) at: $(OUT_DIR)")
	@rm -rf $(OUT_DIR)

# ---------------------------
#   Dependencies
# ---------------------------

.PHONY: out-dir
out-dir:
	$(call log_notice, "Creating output directory for distribution at: $(OUT_DIR)")
	@mkdir -p $(OUT_DIR)


# ---------------------------
# Checks
# ---------------------------
.PHONY: version
version:
	@echo -n "$(VERSION)"

# Fails with the list of what to install, rather than letting a recipe die on
# a bare 'command not found' halfway through a lint run.
.PHONY: tools-check
tools-check:
	@. $(LIB_DIR)/log.sh; \
	missing=""; \
	for exe in $(EXECUTABLES); do \
		if command -v "$$exe" >/dev/null 2>&1; then \
			lib::log::green "Found $$exe in system PATH."; \
		else \
			missing="$$missing $$exe"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		lib::log::red "Missing required tool(s):$$missing"; \
		exit 1; \
	fi; \
	lib::log::green "Found all required tools. Ready to proceed!"

# ---------------------------
# Formatting
# ---------------------------
.PHONY: format
format:
	$(call log_notice, "Formatting all Bash sources with shfmt")
	@shfmt --apply-ignore --write .

# ---------------------------
# Linting
# ---------------------------
.PHONY: lint
lint: tools-check markdownlint actionlint shellcheck shfmt gitleaks

.PHONY: markdownlint
markdownlint:
	@markdownlint -c $(MARKDOWNLINT_CONFIG) '**/*.md' -i 'test/**/*' -i 'secrets/**/*'

.PHONY: actionlint
actionlint:
	@actionlint

.PHONY: gitleaks
gitleaks:
	@gitleaks detect --no-banner --no-git --redact --config $(GITLEAKS_CONFIG) --verbose --source .

.PHONY: shellcheck
shellcheck:
	@shellcheck -x $(SHELL_SOURCES)

.PHONY: shfmt
shfmt:
	@shfmt --apply-ignore --diff .
