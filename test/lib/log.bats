#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
}

# lib::log::write
@test "lib::log::write wraps the message in the given color" {
	run lib::log::write "31m" "boom"

	assert_output "$(printf '\033[1;31mboom\033[0m')"
}

# The message is data: a backslash in a path, a pattern or a password must
# survive verbatim. This is why the module uses printf and not 'echo -e'.
@test "lib::log::write does not interpret escapes in the message" {
	run lib::log::plain 'C:\bin\new and 100% done'

	assert_output 'C:\bin\new and 100% done'
}

@test "lib::log::plain writes the message with no color codes" {
	run lib::log::plain "just text"

	assert_output "just text"
}

# Streams: errors have to reach stderr or cron and CI alerting never see them.
@test "lib::log::red writes to stderr, not stdout" {
	local on_stdout on_stderr

	on_stdout=$(lib::log::red "an error" 2>/dev/null)
	on_stderr=$(lib::log::red "an error" 2>&1 1>/dev/null)

	assert_equal "$on_stdout" ""
	[[ $on_stderr == *"an error"* ]]
}

@test "lib::log::timed_red writes to stderr, not stdout" {
	local on_stdout on_stderr

	on_stdout=$(lib::log::timed_red "an error" 2>/dev/null)
	on_stderr=$(lib::log::timed_red "an error" 2>&1 1>/dev/null)

	assert_equal "$on_stdout" ""
	[[ $on_stderr == *"an error"* ]]
}

@test "the non-error colors write to stdout" {
	local color

	for color in green yellow cyan; do
		local on_stdout
		on_stdout=$("lib::log::$color" "progress" 2>/dev/null)
		[[ $on_stdout == *"progress"* ]] || fail "lib::log::$color did not write to stdout"
	done
}

# lib::log::timed
@test "lib::log::timed prefixes an RFC-3339 timestamp" {
	run lib::log::timed_green "working"

	assert_output --regexp '\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\+|-)[0-9]{2}:[0-9]{2}\]: working'
}
