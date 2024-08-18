# MIT License
# 
# Copyright (c) 2024 FMJ Studios
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
# Sources
# ---------------------------
FIND_FLAGS := -name "*.sh" -type f
SOURCES := $(shell find $(ROOT_DIR) $(FIND_FLAGS))
BUNDLES := scripts lib all

# Only export variables from here since we do not want to mix the top-level
# Makefile's notion of 'SOURCES' with the different sub-makes
export

# ---------------------------
# Constants
# ---------------------------
VERSION := 0.1.0

# Build output
OUT_DIR := $(ROOT_DIR)/dist
SCRIPT_DIR := $(ROOT_DIR)/scripts
LIB_DIR := $(ROOT_DIR)/lib
CI_DIR := $(ROOT_DIR)/.github
CI_LINTER_DIR := $(CI_DIR)/linters
TEST_DIR := $(ROOT_DIR)/test

# Documentation
DOCS_DIR := $(ROOT_DIR)/docs
MARKDOWNLINT_CONFIG := $(CI_LINTER_DIR)/.markdown-lint.yml
GITLEAKS_CONFIG := $(CI_LINTER_DIR)/.gitleaks.toml

# Executables
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

define log
 @case ${2} in \
  gray)    echo -e "\e[90m${1}\e[0m" ;; \
  red)     echo -e "\e[91m${1}\e[0m" ;; \
  green)   echo -e "\e[92m${1}\e[0m" ;; \
  yellow)  echo -e "\e[93m${1}\e[0m" ;; \
  *)       echo -e "\e[97m${1}\e[0m" ;; \
 esac
endef

define log_info
 $(call log, $(1), "gray")
endef

define log_success
 $(call log, $(1), "green")
endef

define log_notice
 $(call log, $(1), "yellow")
endef

define log_attention
 $(call log, $(1), "red")
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
	# do not remove the ending semicolon as it will break the target
	$(foreach type,$(BUNDLES),$(MAKE) build WHAT=$(type);)
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
	$(call log_success, "Building complete tarball bundle into $(OUT_DIR)")
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-$(VERSION).tar.gz" scripts/ lib/ bin/
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-scripts-$(VERSION).tar.gz" scripts/
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-lib-$(VERSION).tar.gz" lib/
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-bin-$(VERSION).tar.gz" bin/
else
	$(call log_success, "Building tarball bundle for $(WHAT)")
	@tar -vzcf "$(OUT_DIR)/$(PROJ_NAME)-$(WHAT)-$(VERSION).tar.gz" -C $(WHAT) .
endif
endif


define TEST_INFO
# Run tests for scripts, the Bash library or the executables.
#
# Arguments:
#   PRINT_HELP: 'y' or 'n'
#   WHAT: 'scripts', 'lib', 'bin'
endef
.PHONY: test
ifeq ($(PRINT_HELP), y)
test:
	echo "$$TEST_INFO"
else
test: update-submodules
ifeq ($(WHAT),)
	$(call log_success, "Testing all Bash sources for!")
	@$(TEST_DIR)/bats/core/bin/bats -r $(TEST_DIR)/lib
else
	$(call log_success, "Testing Bash sources for $(WHAT)")
	@$(TEST_DIR)/bats/core/bin/bats -r $(TEST_DIR)/$(WHAT)
endif
endif

# ---------------------------
#   Housekeeping
# ---------------------------

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

.PHONY: tools-check
tools-check:
	$(foreach exe,$(EXECUTABLES), $(if $(shell command -v $(exe) 2> /dev/null), $(info Found $(exe)), $(info Please install $(exe))))

# ---------------------------
# Linting
# ---------------------------
.PHONY: lint
lint: markdownlint actionlint shellcheck shfmt gitleaks

.PHONY: markdownlint
markdownlint:
	@markdownlint -c $(MARKDOWNLINT_CONFIG) '**/*.md' -i 'test/**/*'

.PHONY: actionlint
actionlint:
	@actionlint

.PHONY: gitleaks
gitleaks:
	@gitleaks detect --no-banner --no-git --redact --config $(GITLEAKS_CONFIG) --verbose --source .

.PHONY: shellcheck
shellcheck:
	@shellcheck scripts/*.sh -x
	@shellcheck lib/*.sh -x
	@shellcheck bin/* -x

.PHONY: shfmt
shfmt:
	@shfmt --apply-ignore --diff .