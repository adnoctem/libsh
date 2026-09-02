#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/paths.sh"

	TEST_TMP=$(mktemp -d)
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# lib::paths::ensure_existence -- creates the PARENT of the given path, so
# callers hand it the file they are about to write.
@test "lib::paths::ensure_existence creates the parent directory of a file" {
	lib::paths::ensure_existence "$TEST_TMP/deeply/nested/dump.sql"

	assert [ -d "$TEST_TMP/deeply/nested" ]
}

@test "lib::paths::ensure_existence does not create the file itself" {
	lib::paths::ensure_existence "$TEST_TMP/deeply/nested/dump.sql"

	refute [ -e "$TEST_TMP/deeply/nested/dump.sql" ]
}

@test "lib::paths::ensure_existence leaves an existing path alone" {
	mkdir -p "$TEST_TMP/existing"
	printf 'keep me\n' >"$TEST_TMP/existing/file.txt"

	lib::paths::ensure_existence "$TEST_TMP/existing/file.txt"

	assert_equal "$(cat "$TEST_TMP/existing/file.txt")" "keep me"
}

# lib::paths::ensure_directory -- creates the path itself, for callers that
# have a directory rather than a file.
@test "lib::paths::ensure_directory creates the directory itself" {
	lib::paths::ensure_directory "$TEST_TMP/a/b/c"

	assert [ -d "$TEST_TMP/a/b/c" ]
}

@test "lib::paths::ensure_directory is a no-op on an existing directory" {
	mkdir -p "$TEST_TMP/already"
	printf 'keep me\n' >"$TEST_TMP/already/file.txt"

	lib::paths::ensure_directory "$TEST_TMP/already"

	assert [ -f "$TEST_TMP/already/file.txt" ]
}
