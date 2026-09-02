#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
	source "$REPO_ROOT/lib/ui.sh"

	TEST_TMP=$(mktemp -d)

	# 'script' runs its argument through $SHELL, which is zsh here, and zsh
	# reads 'read -p' as a coprocess request. The helper carries its own
	# bash shebang so the TTY tests exercise the real code path.
	cat >"$TEST_TMP/confirm.sh" <<-HELPER
		#!/usr/bin/env bash
		cd "$REPO_ROOT" || exit 1
		. lib/log.sh
		. lib/ui.sh
		if lib::ui::confirm 'Proceed?'; then echo CONFIRMED; else echo DECLINED; fi
	HELPER
	chmod +x "$TEST_TMP/confirm.sh"
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# lib::ui::confirm -- bats gives the tests no TTY, which is exactly the
# unattended case these guards exist for.
@test "lib::ui::confirm answers yes without a TTY when the default is y" {
	run lib::ui::confirm "Proceed?" "y"

	assert_success
}

@test "lib::ui::confirm answers no without a TTY when the default is n" {
	run lib::ui::confirm "Proceed?" "n"

	assert_failure
}

# The important one: no TTY and no default must refuse rather than assume.
# Every destructive script in scripts/ relies on this to stop a cron run
# that never had an operator to answer it.
@test "lib::ui::confirm refuses without a TTY when no default is given" {
	run lib::ui::confirm "Proceed?"

	assert_failure
}

@test "lib::ui::confirm explains why it refused" {
	run lib::ui::confirm "Delete everything?"

	assert_output --partial "needs a TTY"
	assert_output --partial "Delete everything?"
}

@test "lib::ui::confirm accepts a typed yes on a terminal" {
	if ! command -v script >/dev/null; then
		skip "the 'script' utility is needed to fake a TTY"
	fi

	run script -qec "$TEST_TMP/confirm.sh" /dev/null <<<"y"

	assert_output --partial "CONFIRMED"
}

@test "lib::ui::confirm treats a bare enter as no when there is no default" {
	if ! command -v script >/dev/null; then
		skip "the 'script' utility is needed to fake a TTY"
	fi

	run script -qec "$TEST_TMP/confirm.sh" /dev/null <<<""

	assert_output --partial "DECLINED"
	refute_output --partial "CONFIRMED"
}

# lib::ui::spinner -- without a TTY it degrades to a plain wait, so cron
# and CI logs do not fill with carriage-return spam.
@test "lib::ui::spinner returns the watched process's exit code" {
	sleep 0.2 &
	local pid=$!

	lib::ui::spinner "$pid" "waiting" >/dev/null
	assert_equal "$?" "0"
}

@test "lib::ui::spinner propagates a failure from the watched process" {
	bash -c 'sleep 0.1; exit 3' &
	local pid=$!
	local rc=0

	lib::ui::spinner "$pid" "waiting" >/dev/null || rc=$?
	assert_equal "$rc" "3"
}

@test "lib::ui::spinner prints no animation without a TTY" {
	sleep 0.2 &
	local pid=$!

	lib::ui::spinner "$pid" "waiting" >"$TEST_TMP/rendered"

	assert_equal "$(cat "$TEST_TMP/rendered")" ""
}
