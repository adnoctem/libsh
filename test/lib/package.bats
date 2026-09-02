#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/package.sh"
}

# lib::package::is_executable
@test "lib::package::is_executable succeeds for a binary on PATH" {
	run lib::package::is_executable bash

	assert_success
}

@test "lib::package::is_executable succeeds for a shell builtin" {
	run lib::package::is_executable cd

	assert_success
}

@test "lib::package::is_executable fails for a missing binary" {
	run lib::package::is_executable definitely-not-a-real-binary

	assert_failure
}

# An unset argument must not read as "found": every prerequisite check in
# scripts/ depends on this failing closed.
@test "lib::package::is_executable fails for an empty argument" {
	run lib::package::is_executable ""

	assert_failure
}
