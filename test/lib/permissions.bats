#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/permissions.sh"

	TEST_TMP=$(mktemp -d)
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# lib::permissions::check_if_root -- EUID is read-only in bash, so the test
# asserts against whoever is actually running it.
@test "lib::permissions::check_if_root reflects the current user" {
	run lib::permissions::check_if_root

	if [[ $EUID -eq 0 ]]; then
		assert_success
	else
		assert_failure
	fi
}

# lib::permissions::run_as_root
@test "lib::permissions::run_as_root delegates to sudo when not root" {
	if [[ $EUID -eq 0 ]]; then
		skip "already root: the sudo path is unreachable"
	fi

	# A stand-in for sudo, so the test never asks for a password or runs
	# anything privileged.
	cat >"$TEST_TMP/sudo" <<-'FAKE'
		#!/usr/bin/env bash
		printf 'sudo called with: %s\n' "$*"
	FAKE
	chmod +x "$TEST_TMP/sudo"

	PATH="$TEST_TMP:$PATH" run lib::permissions::run_as_root apt-get update

	assert_output "sudo called with: apt-get update"
}

@test "lib::permissions::run_as_root runs the command directly when root" {
	if [[ $EUID -ne 0 ]]; then
		skip "not root: the direct path is unreachable"
	fi

	run lib::permissions::run_as_root echo "ran directly"

	assert_output "ran directly"
}

@test "lib::permissions::run_as_root passes arguments through unsplit" {
	if [[ $EUID -eq 0 ]]; then
		skip "already root: the sudo path is unreachable"
	fi

	cat >"$TEST_TMP/sudo" <<-'FAKE'
		#!/usr/bin/env bash
		for arg in "$@"; do printf '[%s]\n' "$arg"; done
	FAKE
	chmod +x "$TEST_TMP/sudo"

	PATH="$TEST_TMP:$PATH" run lib::permissions::run_as_root cp -- "a file" "another file"

	assert_output "[cp]
[--]
[a file]
[another file]"
}

@test "lib::permissions::run_as_root propagates the command's exit code" {
	if [[ $EUID -eq 0 ]]; then
		skip "already root: the sudo path is unreachable"
	fi

	printf '#!/usr/bin/env bash\nexit 7\n' >"$TEST_TMP/sudo"
	chmod +x "$TEST_TMP/sudo"

	PATH="$TEST_TMP:$PATH" run lib::permissions::run_as_root false

	assert_failure 7
}
