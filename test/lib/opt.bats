#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"

	# The spec every test parses against unless it defines its own.
	# shellcheck disable=SC2034 # read by the dynamically loaded option parser
	OPTS=(
		"-u,--username:username:1:required"
		"-p,--password:password:1:optional"
		"--dry-run:dry_run:0:optional"
	)
	# shellcheck disable=SC2034 # read by the dynamically loaded option parser
	declare -gA OPTS_HELP=(
		[username]="Username"
		[password]="Password"
		[dry_run]="Dry run"
	)
	declare -gA OPTS_VALUES=()
}

# lib::opt::parse -- values
@test "lib::opt::parse reads a short value flag" {
	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[username]:-}" "alice"
}

@test "lib::opt::parse reads a long value flag" {
	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[password]:-}" "s3cret"
}

@test "lib::opt::parse sets a boolean flag to 1" {
	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[dry_run]:-}" "1"
}

@test "lib::opt::parse leaves an unpassed boolean flag unset" {
	lib::opt::parse -u alice

	assert_equal "${OPTS_VALUES[dry_run]:-unset}" "unset"
}

@test "lib::opt::parse takes a value starting with a dash literally" {
	lib::opt::parse -u alice -p -notaflagbutlookslikeone

	assert_equal "${OPTS_VALUES[password]:-}" "-notaflagbutlookslikeone"
}

# This is the exact case that broke the original hand-rolled parsing loop,
# which matched '-p' against the leading character of the value.
@test "lib::opt::parse regression: short flags do not eat their own value" {
	lib::opt::parse -u myuser -p mypass

	assert_equal "${OPTS_VALUES[username]:-}" "myuser"
	assert_equal "${OPTS_VALUES[password]:-}" "mypass"
}

# lib::opt::parse -- validation
@test "lib::opt::parse fails when a required flag is missing" {
	run lib::opt::parse --password onlypassword

	assert_failure
	assert_output --partial "Missing required option(s): --username"
}

@test "lib::opt::parse prints usage when a required flag is missing" {
	run lib::opt::parse --password onlypassword

	assert_output --partial "Usage:"
}

@test "lib::opt::parse rejects an unknown flag" {
	run lib::opt::parse -u alice --bogus

	assert_failure
	assert_output --partial "Unknown option: --bogus"
}

@test "lib::opt::parse rejects a value flag with no value" {
	run lib::opt::parse -u alice -p

	assert_failure
	assert_output --partial "Option '-p' requires a value."
}

# lib::opt::usage / --help
@test "lib::opt::parse exits 0 on --help even with required flags unmet" {
	# shellcheck disable=SC2034 # read by the dynamically loaded option parser
	OPTS=(
		"-u,--username:username:1:required"
		"-h,--help:help:0:optional"
	)

	run lib::opt::parse --help

	assert_success
	assert_output --partial "Usage:"
}

@test "lib::opt::usage lists every flag from the spec" {
	run lib::opt::usage

	assert_output --partial "-u, --username <value> (required)"
	assert_output --partial "-p, --password <value>"
	assert_output --partial "--dry-run"
}

@test "lib::opt::usage renders the description from OPTS_HELP" {
	run lib::opt::usage

	assert_output --partial "Username"
	assert_output --partial "Dry run"
}
