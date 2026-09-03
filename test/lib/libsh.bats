#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
}

# The library is meant to be sourced into scripts that have their own
# functions, so every name it defines has to be reachable as
# lib::<file>::<function> -- both to avoid collisions and to make the set
# of provided functions enumerable.
@test "every function in lib/ is namespaced lib::<file>::<function>" {
	local violations=()

	for file in "$REPO_ROOT"/lib/*.sh; do
		local module
		module=$(basename "$file" .sh)

		local name
		while read -r name; do
			[[ -z $name ]] && continue
			[[ $name == "lib::${module}::"* ]] || violations+=("$(basename "$file"): $name")
		done < <(grep -oE '^(function )?[A-Za-z0-9_:]+\(\)' "$file" | sed 's/^function //; s/()$//')
	done

	assert_equal "${violations[*]:-}" ""
}

# lib/lib.sh is the single entrypoint scripts will source once the library
# becomes its own project, so it has to expose the whole surface: a module
# that lands in lib/ without being reachable through it is a silent gap.
@test "lib/lib.sh exposes every function the modules define" {
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
