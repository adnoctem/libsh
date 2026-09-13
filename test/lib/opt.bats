#!/usr/bin/env bats

setup() {
	REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

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

}

# lib::opt::parse -- values
@test "lib::opt::parse reads a short value flag" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[username]:-}" "alice"
}

@test "lib::opt::parse reads a long value flag" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[password]:-}" "s3cret"
}

@test "lib::opt::parse sets a boolean flag to 1" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u alice --password s3cret --dry-run

	assert_equal "${OPTS_VALUES[dry_run]:-}" "1"
}

@test "lib::opt::parse leaves an unpassed boolean flag unset" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u alice

	assert_equal "${OPTS_VALUES[dry_run]:-unset}" "unset"
}

@test "lib::opt::parse takes a value starting with a dash literally" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u alice -p -notaflagbutlookslikeone

	assert_equal "${OPTS_VALUES[password]:-}" "-notaflagbutlookslikeone"
}

# This is the exact case that broke the original hand-rolled parsing loop,
# which matched '-p' against the leading character of the value.
@test "lib::opt::parse regression: short flags do not eat their own value" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	lib::opt::parse -u myuser -p mypass

	assert_equal "${OPTS_VALUES[username]:-}" "myuser"
	assert_equal "${OPTS_VALUES[password]:-}" "mypass"
}

# lib::opt::parse -- validation
@test "lib::opt::parse fails when a required flag is missing" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::parse --password onlypassword

	assert_failure
	assert_output --partial "Missing required option(s): --username"
}

@test "lib::opt::parse prints usage when a required flag is missing" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::parse --password onlypassword

	assert_output --partial "Usage:"
}

@test "lib::opt::parse rejects an unknown flag" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::parse -u alice --bogus

	assert_failure
	assert_output --partial "Unknown option: --bogus"
}

@test "lib::opt::parse rejects a value flag with no value" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::parse -u alice -p

	assert_failure
	assert_output --partial "Option '-p' requires a value."
}

# lib::opt::usage / --help
@test "lib::opt::parse returns 0 on --help even with required flags unmet" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

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
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::usage

	assert_output --partial "-u, --username <value> (required)"
	assert_output --partial "-p, --password <value>"
	assert_output --partial "--dry-run"
}

@test "lib::opt::usage renders the description from OPTS_HELP" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run lib::opt::usage

	assert_output --partial "Username"
	assert_output --partial "Dry run"
}

@test "help returns to the caller and sets an explicit marker" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	# shellcheck disable=SC2030 # BATS tests intentionally have independent state
	OPTS=("-h,--help:help:0:optional")
	lib::opt::parse --help >/dev/null
	assert_equal "${OPTS_VALUES[help]:-}" 1
}

@test "library-local parser arrays preserve enclosing parser state on success help and failure" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	local before
	OPTS_VALUES[sentinel]=unchanged
	# shellcheck disable=SC2031 # setup initializes OPTS separately for each test
	before=$(declare -p OPTS OPTS_HELP OPTS_VALUES)
	parse_local() {
		# shellcheck disable=SC2034 # consumed by the dynamically loaded parser
		local -a OPTS=("-n,--name:name:1:required" "-h,--help:help:0:optional")
		# shellcheck disable=SC2034 # consumed by the dynamically loaded parser
		local -A OPTS_HELP=([name]=Name) OPTS_VALUES=()
		lib::opt::parse "$@"
	}
	parse_local --name 'two words'
	parse_local --help >/dev/null
	if parse_local --bogus >/dev/null 2>&1; then return 1; fi
	assert_equal "$(declare -p OPTS OPTS_HELP OPTS_VALUES)" "$before"
}

@test "parser failures put all diagnostics including usage on stderr" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	local output_file="$BATS_TEST_TMPDIR/stdout"
	if lib::opt::parse --password value >"$output_file" 2>/dev/null; then return 1; fi
	[[ ! -s $output_file ]]
}

@test "empty locally scoped option specs work under strict shell options" {
	# Keep associative fixtures in the test scope for Bash 4.0.
	# shellcheck disable=SC2034
	local -A OPTS_HELP=([username]="Username" [password]="Password" [dry_run]="Dry run") OPTS_VALUES=()

	run bash -c '
		set -euo pipefail
		source "$1/lib/lib.sh"
		work() {
			# shellcheck disable=SC2034 # consumed by the dynamically loaded parser
		local -a OPTS=()
			# shellcheck disable=SC2034 # consumed by the dynamically loaded parser
		local -A OPTS_HELP=() OPTS_VALUES=()
			lib::opt::parse
		}
		work
	' _ "$REPO_ROOT"
	assert_success
}
