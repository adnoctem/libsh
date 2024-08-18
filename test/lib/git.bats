#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/git.sh"
}

# git::toplevel
@test 'Validate git::toplevel succeeds with an empty array' {
	curdir=$(pwd)

	run git::toplevel
	assert_output --partial "$curdir"
}
