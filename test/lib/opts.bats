#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
	source "$REPO_ROOT/lib/opts.sh"

	# The spec every test parses against unless it defines its own.
	OPTS=(
		"-u,--username:username:1:required"
		"-p,--password:password:1:optional"
		"--dry-run:dry_run:0:optional"
	)
	declare -gA OPTS_HELP=(
		[username]="Username"
		[password]="Password"
		[dry_run]="Dry run"
	)
	declare -gA OPTS_VALUES=()
}

# lib::opts::parse -- values
@test "lib::opts::parse reads a short value flag" {
	lib::opts::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[username]:-}" "alice"
}

@test "lib::opts::parse reads a long value flag" {
	lib::opts::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[password]:-}" "s3cret"
}

@test "lib::opts::parse sets a boolean flag to 1" {
	lib::opts::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[dry_run]:-}" "1"
}

@test "lib::opts::parse leaves an unpassed boolean flag unset" {
	lib::opts::parse -u alice

	assert_equal "${OPTS_VALUES[dry_run]:-unset}" "unset"
}

@test "lib::opts::parse takes a value starting with a dash literally" {
	lib::opts::parse -u alice -p -notaflagbutlookslikeone

	assert_equal "${OPTS_VALUES[password]:-}" "-notaflagbutlookslikeone"
}

# This is the exact case that broke the original hand-rolled parsing loop,
# which matched '-p' against the leading character of the value.
@test "lib::opts::parse regression: short flags do not eat their own value" {
	lib::opts::parse -u myuser -p mypass

	assert_equal "${OPTS_VALUES[username]:-}" "myuser"
	assert_equal "${OPTS_VALUES[password]:-}" "mypass"
}

# lib::opts::parse -- validation
@test "lib::opts::parse fails when a required flag is missing" {
	run lib::opts::parse --password onlypassword

	assert_failure
	assert_output --partial "Missing required option(s): --username"
}

@test "lib::opts::parse prints usage when a required flag is missing" {
	run lib::opts::parse --password onlypassword

	assert_output --partial "Usage:"
}

@test "lib::opts::parse rejects an unknown flag" {
	run lib::opts::parse -u alice --bogus

	assert_failure
	assert_output --partial "Unknown option: --bogus"
}

@test "lib::opts::parse rejects a value flag with no value" {
	run lib::opts::parse -u alice -p

	assert_failure
	assert_output --partial "Option '-p' requires a value."
}

# lib::opts::usage / --help
@test "lib::opts::parse exits 0 on --help even with required flags unmet" {
	OPTS=(
		"-u,--username:username:1:required"
		"-h,--help:help:0:optional"
	)

	run lib::opts::parse --help

	assert_success
	assert_output --partial "Usage:"
}

@test "lib::opts::usage lists every flag from the spec" {
	run lib::opts::usage

	assert_output --partial "-u, --username <value> (required)"
	assert_output --partial "-p, --password <value>"
	assert_output --partial "--dry-run"
}

@test "lib::opts::usage renders the description from OPTS_HELP" {
	run lib::opts::usage

	assert_output --partial "Username"
	assert_output --partial "Dry run"
}
