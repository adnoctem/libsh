#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/git.sh"
}

# lib::git::toplevel
@test 'lib::git::toplevel returns a parent directory of the test location' {
	curdir=$(pwd)

	run lib::git::toplevel
	assert_output --partial "$curdir"
}

# lib::git::remote_exists
@test "lib::git::remote_exists succeeds with a valid remote" {
	run lib::git::remote_exists origin
	assert_success
}

@test "lib::git::remote_exists fails with an invalid remote" {
	run lib::git::remote_exists github
	assert_failure
}

# lib::git::branch_exists
@test "lib::git::branch_exists succeeds with a valid branch" {
	run lib::git::branch_exists main
	assert_success
}

@test "lib::git::remote_exists fails with an invalid branch" {
	run lib::git::branch_exists master
	assert_failure
}
