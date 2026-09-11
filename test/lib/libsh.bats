#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
}

# Keep public APIs enumerable by lib:: and private implementation helpers
# under __libsh_. Both namespaces identify the containing module.
@test "library functions follow the public or private naming convention" {
	local violations=()

	for file in "$REPO_ROOT"/lib/*.sh; do
		local module
		module=$(basename "$file" .sh)

		local name public_pattern private_pattern
		public_pattern="^lib::${module}::[a-z][a-z0-9_]*$"
		private_pattern="^__libsh_${module}_[a-z][a-z0-9_]*$"
		while read -r name; do
			[[ -z $name ]] && continue
			[[ $name =~ $public_pattern || $name =~ $private_pattern ]] || violations+=("$(basename "$file"): $name")
		done < <(grep -oE '^(function )?[A-Za-z0-9_:]+\(\)' "$file" | sed 's/^function //; s/()$//')
	done

	assert_equal "${violations[*]:-}" ""
}

# The entrypoint must load both public APIs and their private dependencies.
@test "lib/lib.sh loads every public function and private helper" {
	local missing=()

	source "$REPO_ROOT/lib/lib.sh"

	local file name
	for file in "$REPO_ROOT"/lib/*.sh; do
		[[ "$(basename "$file")" == "lib.sh" ]] && continue

		while read -r name; do
			[[ -z $name ]] && continue
			declare -F "$name" >/dev/null || missing+=("$name")
		done < <(grep -oE '^(function )?[A-Za-z0-9_:]+\(\)' "$file" | sed 's/^function //; s/()$//')
	done

	assert_equal "${missing[*]:-}" ""
}

@test "lib/lib.sh reports how many modules it loaded" {
	source "$REPO_ROOT/lib/lib.sh"

	# The arithmetic context strips the leading whitespace BSD/macOS 'wc'
	# pads its count with, which a bare command substitution would not.
	local expected
	expected=$(($(find "$REPO_ROOT/lib" -maxdepth 1 -name '*.sh' ! -name 'lib.sh' | wc -l)))

	assert_equal "${LIBSH_LOADED:-0}" "$expected"
}

@test "every file in lib/ declares its shell for shellcheck" {
	local violations=()

	for file in "$REPO_ROOT"/lib/*.sh; do
		head -n 1 "$file" | grep -q 'shellcheck shell=bash' || violations+=("$(basename "$file")")
	done

	assert_equal "${violations[*]:-}" ""
}

# A module without a test file is how coverage quietly rots: this fails the
# moment lib/<module>.sh lands without test/lib/<module>.bats next to it.
# lib.sh is the exception -- the entrypoint is covered by this file.
@test "every module in lib/ has a matching .bats file" {
	local missing=()

	local file module
	for file in "$REPO_ROOT"/lib/*.sh; do
		module=$(basename "$file" .sh)

		[[ $module == "lib" ]] && continue
		[[ -f "$REPO_ROOT/test/lib/${module}.bats" ]] || missing+=("${module}.sh")
	done

	assert_equal "${missing[*]:-}" ""
}
