#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"
	lib::load_extensions ui

	TEST_TMP=$(mktemp -d)

	# 'script' runs its argument through $SHELL, which is zsh here, and zsh
	# reads 'read -p' as a coprocess request. The helper carries its own
	# bash shebang so the TTY tests exercise the real code path.
	cat >"$TEST_TMP/confirm.sh" <<-HELPER
		#!/usr/bin/env bash
		cd "$REPO_ROOT" || exit 1
		. lib/log.sh
		. extensions/libui.sh
		if ext::ui::confirm 'Proceed?'; then echo CONFIRMED; else echo DECLINED; fi
	HELPER
	chmod +x "$TEST_TMP/confirm.sh"
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# 'script's syntax for running a command differs: GNU/util-linux script
# (Linux) takes '-c COMMAND'; BSD script (macOS) takes the command as
# trailing positional arguments after the log file instead.
run_in_fake_tty() {
	local cmd=$1

	if [[ $(uname) == "Darwin" ]]; then
		script -q /dev/null "$cmd"
	else
		script -qec "$cmd" /dev/null
	fi
}

# ext::ui::confirm -- bats gives the tests no TTY, which is exactly the
# unattended case these guards exist for.
@test "ext::ui::confirm answers yes without a TTY when the default is y" {
	run ext::ui::confirm "Proceed?" "y"

	assert_success
}

@test "ext::ui::confirm answers no without a TTY when the default is n" {
	run ext::ui::confirm "Proceed?" "n"

	assert_failure
}

# The important one: no TTY and no default must refuse rather than assume.
# Every destructive script in scripts/ relies on this to stop a cron run
# that never had an operator to answer it.
@test "ext::ui::confirm refuses without a TTY when no default is given" {
	run ext::ui::confirm "Proceed?"

	assert_failure
}

@test "ext::ui::confirm explains why it refused" {
	run ext::ui::confirm "Delete everything?"

	assert_output --partial "needs a TTY"
	assert_output --partial "Delete everything?"
}

@test "ext::ui::confirm accepts a typed yes on a terminal" {
	if ! command -v script >/dev/null; then
		skip "the 'script' utility is needed to fake a TTY"
	fi
	# BSD script (macOS) doesn't reliably forward redirected/piped stdin
	# into the pty session it spawns -- it's built for interactively
	# recording a live terminal, not for scripted input injection. The
	# typed character arrives late or corrupted (observed: control bytes
	# then the character, after 'read' already saw an empty line). This is
	# a limitation of faking a TTY this way, not a bug in
	# ext::ui::confirm -- the no-TTY tests above cover its actually
	# safety-critical path.
	if [[ $(uname) == "Darwin" ]]; then
		skip "BSD script does not reliably forward piped stdin into its pty"
	fi

	run run_in_fake_tty "$TEST_TMP/confirm.sh" <<<"y"

	assert_output --partial "CONFIRMED"
}

@test "ext::ui::confirm treats a bare enter as no when there is no default" {
	if ! command -v script >/dev/null; then
		skip "the 'script' utility is needed to fake a TTY"
	fi
	if [[ $(uname) == "Darwin" ]]; then
		skip "BSD script does not reliably forward piped stdin into its pty"
	fi

	run run_in_fake_tty "$TEST_TMP/confirm.sh" <<<""

	assert_output --partial "DECLINED"
	refute_output --partial "CONFIRMED"
}

# ext::ui::spinner -- without a TTY it degrades to a plain wait, so cron
# and CI logs do not fill with carriage-return spam.
@test "ext::ui::spinner returns the watched process's exit code" {
	sleep 0.2 &
	local pid=$!

	ext::ui::spinner "$pid" "waiting" >/dev/null
	assert_equal "$?" "0"
}

@test "ext::ui::spinner propagates a failure from the watched process" {
	bash -c 'sleep 0.1; exit 3' &
	local pid=$!
	local rc=0

	ext::ui::spinner "$pid" "waiting" >/dev/null || rc=$?
	assert_equal "$rc" "3"
}

@test "ext::ui::spinner prints no animation without a TTY" {
	sleep 0.2 &
	local pid=$!

	ext::ui::spinner "$pid" "waiting" >"$TEST_TMP/rendered"

	assert_equal "$(cat "$TEST_TMP/rendered")" ""
}
