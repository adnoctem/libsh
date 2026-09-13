#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"
	lib::load_extensions git
}

# ext::git::toplevel
@test 'ext::git::toplevel returns a parent directory of the test location' {
	curdir=$(pwd)

	run ext::git::toplevel
	assert_output --partial "$curdir"
}

# ext::git::remote_exists
@test "ext::git::remote_exists succeeds with a valid remote" {
	run ext::git::remote_exists origin
	assert_success
}

@test "ext::git::remote_exists fails with an invalid remote" {
	run ext::git::remote_exists github
	assert_failure
}

# ext::git::branch_exists
@test "ext::git::branch_exists succeeds with a valid branch" {
	run ext::git::branch_exists main
	assert_success
}

@test "ext::git::remote_exists fails with an invalid branch" {
	run ext::git::branch_exists master
	assert_failure
}
