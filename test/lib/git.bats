#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/git.sh"
}

# git::toplevel
@test 'git::toplevel returns a parent directory of the test location' {
	curdir=$(pwd)

	run git::toplevel
	assert_output --partial "$curdir"
}

# git::remote_exists
@test "git::remote_exists succeeds with a valid remote" {
	run git::remote_exists origin
	assert_success
}

@test "git::remote_exists fails with an invalid remote" {
	run git::remote_exists github
	assert_failure
}

# git::branch_exists
@test "git::branch_exists succeeds with a valid branch" {
	run git::branch_exists main
	assert_success
}

@test "git::remote_exists fails with an invalid branch" {
	run git::branch_exists master
	assert_failure
}
