#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
	source "$REPO_ROOT/lib/secret.sh"

	TEST_TMP=$(mktemp -d)
	SECRET_FILE="$TEST_TMP/password"
	printf 'p@ss:w/rd!#100%%\n' >"$SECRET_FILE"
	chmod 600 "$SECRET_FILE"
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# lib::secret::from_file
@test "lib::secret::from_file returns the secret verbatim" {
	run lib::secret::from_file "$SECRET_FILE"

	assert_success
	assert_output 'p@ss:w/rd!#100%'
}

# The trailing newline is an editor artifact, not part of the password.
@test "lib::secret::from_file reads only the first line" {
	printf 'first-line\nsecond-line\n' >"$SECRET_FILE"

	run lib::secret::from_file "$SECRET_FILE"

	assert_output "first-line"
}

@test "lib::secret::from_file handles a file with no trailing newline" {
	printf 'no-newline-here' >"$SECRET_FILE"

	run lib::secret::from_file "$SECRET_FILE"

	assert_success
	assert_output "no-newline-here"
}

# Callers capture stdout with a command substitution, so a warning that
# lands there would be captured as part of the password.
@test "lib::secret::from_file keeps warnings off stdout" {
	chmod 644 "$SECRET_FILE"

	local captured
	captured=$(lib::secret::from_file "$SECRET_FILE" 2>/dev/null)

	assert_equal "$captured" 'p@ss:w/rd!#100%'
}

@test "lib::secret::from_file warns about world-readable permissions" {
	chmod 644 "$SECRET_FILE"

	local warning
	warning=$(lib::secret::from_file "$SECRET_FILE" 2>&1 1>/dev/null)

	[[ $warning == *"mode 644"* ]]
}

@test "lib::secret::from_file stays quiet for a 600 file" {
	local warning
	warning=$(lib::secret::from_file "$SECRET_FILE" 2>&1 1>/dev/null)

	assert_equal "$warning" ""
}

@test "lib::secret::from_file fails on a missing file" {
	run lib::secret::from_file "$TEST_TMP/does-not-exist"

	assert_failure
	assert_output --partial "does not exist"
}

@test "lib::secret::from_file fails on an empty file" {
	: >"$SECRET_FILE"

	run lib::secret::from_file "$SECRET_FILE"

	assert_failure
	assert_output --partial "is empty"
}

@test "lib::secret::from_file fails on a file it cannot read" {
	chmod 000 "$SECRET_FILE"

	run lib::secret::from_file "$SECRET_FILE"

	# root can read anything, so the unreadable case cannot be provoked there.
	if [[ $EUID -eq 0 ]]; then
		skip "running as root: permissions do not apply"
	fi

	assert_failure
	assert_output --partial "not readable"
}
