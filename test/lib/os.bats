#!/usr/bin/env bats

setup() {
	REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"

	TEST_TMP=$(mktemp -d)
	ORIGINAL_HOME="$HOME"
	ORIGINAL_PWD="$PWD"
	export HOME="$TEST_TMP/home"
	mkdir -p "$HOME"

	ORIGINAL_PATH="$PATH"
	mkdir -p "$TEST_TMP/bin"
	export PATH="$TEST_TMP/bin:$PATH"

	# Never let the real environment's XDG_* vars leak into a test that
	# means to exercise the spec's own fallback defaults.
	unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME

	# Default every test to a faked non-Darwin 'uname', so the "falls back
	# to ~/.config"-style tests are deterministic regardless of which CI
	# platform actually runs them -- without this, those tests only pass
	# by accident on Linux runners and fail for real on macOS ones, since
	# the function would then correctly take the real Darwin branch.
	# Darwin-specific tests override this via fake_uname_darwin below.
	cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Linux"
	FAKE
	chmod +x "$TEST_TMP/bin/uname"
}

# Install a fake 'uname' reporting Darwin, so the macOS-native path branch
# can be exercised on any CI platform, not just a real Mac.
fake_uname_darwin() {
	cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Darwin"
	FAKE
	chmod +x "$TEST_TMP/bin/uname"
}

# lib::os::ensure_existence -- creates the PARENT of the given path, so
# callers hand it the file they are about to write.
@test "lib::os::ensure_existence creates the parent directory of a file" {
	lib::os::ensure_existence "$TEST_TMP/deeply/nested/dump.sql"

	assert [ -d "$TEST_TMP/deeply/nested" ]
}

@test "lib::os::ensure_existence does not create the file itself" {
	lib::os::ensure_existence "$TEST_TMP/deeply/nested/dump.sql"

	refute [ -e "$TEST_TMP/deeply/nested/dump.sql" ]
}

@test "lib::os::ensure_existence leaves an existing path alone" {
	mkdir -p "$TEST_TMP/existing"
	printf 'keep me\n' >"$TEST_TMP/existing/file.txt"

	lib::os::ensure_existence "$TEST_TMP/existing/file.txt"

	assert_equal "$(cat "$TEST_TMP/existing/file.txt")" "keep me"
}

# lib::os::ensure_directory -- creates the path itself, for callers that
# have a directory rather than a file.
@test "lib::os::ensure_directory creates the directory itself" {
	lib::os::ensure_directory "$TEST_TMP/a/b/c"

	assert [ -d "$TEST_TMP/a/b/c" ]
}

@test "lib::os::ensure_directory is a no-op on an existing directory" {
	mkdir -p "$TEST_TMP/already"
	printf 'keep me\n' >"$TEST_TMP/already/file.txt"

	lib::os::ensure_directory "$TEST_TMP/already"

	assert [ -f "$TEST_TMP/already/file.txt" ]
}

# lib::os::config_home / data_home / cache_home / state_home -- the XDG
# Base Directory Specification's four user directories, each honouring its
# XDG_*_HOME override with the spec's documented fallback.
@test 'lib::os::config_home falls back to $HOME/.config' {
	run lib::os::config_home

	assert_output "$HOME/.config"
}

@test "lib::os::config_home honours XDG_CONFIG_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CONFIG_HOME="$TEST_TMP/custom-config"

	run lib::os::config_home

	assert_output "$TEST_TMP/custom-config"
}

@test "lib::os::config_home nests an app name under the base directory" {
	run lib::os::config_home libsh

	assert_output "$HOME/.config/libsh"
}

@test "lib::os::config_home falls back to ~/Library/Application Support on Darwin" {
	fake_uname_darwin

	run lib::os::config_home

	assert_output "$HOME/Library/Application Support"
}

@test "lib::os::config_home nests an app name under the Darwin base directory" {
	fake_uname_darwin

	run lib::os::config_home libsh

	assert_output "$HOME/Library/Application Support/libsh"
}

@test "lib::os::config_home still honours XDG_CONFIG_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CONFIG_HOME="$TEST_TMP/custom-config"

	run lib::os::config_home

	assert_output "$TEST_TMP/custom-config"
}

@test 'lib::os::data_home falls back to $HOME/.local/share' {
	run lib::os::data_home

	assert_output "$HOME/.local/share"
}

@test "lib::os::data_home honours XDG_DATA_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_DATA_HOME="$TEST_TMP/custom-data"

	run lib::os::data_home

	assert_output "$TEST_TMP/custom-data"
}

@test "lib::os::data_home nests an app name under the base directory" {
	run lib::os::data_home libsh

	assert_output "$HOME/.local/share/libsh"
}

@test "lib::os::data_home falls back to ~/Library on Darwin with no app name" {
	fake_uname_darwin

	run lib::os::data_home

	assert_output "$HOME/Library"
}

# Darwin nests the app name before a fixed 'Data' leaf (~/Library/<app>/Data),
# the reverse of config/cache's app-last shape -- matches gopskit's own
# paths_darwin.go, not smoothed over to look consistent with the others.
@test "lib::os::data_home nests as <app>/Data on Darwin" {
	fake_uname_darwin

	run lib::os::data_home libsh

	assert_output "$HOME/Library/libsh/Data"
}

@test "lib::os::data_home still honours XDG_DATA_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_DATA_HOME="$TEST_TMP/custom-data"

	run lib::os::data_home libsh

	assert_output "$TEST_TMP/custom-data/libsh"
}

@test 'lib::os::cache_home falls back to $HOME/.cache' {
	run lib::os::cache_home

	assert_output "$HOME/.cache"
}

@test "lib::os::cache_home honours XDG_CACHE_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CACHE_HOME="$TEST_TMP/custom-cache"

	run lib::os::cache_home

	assert_output "$TEST_TMP/custom-cache"
}

@test "lib::os::cache_home nests an app name under the base directory" {
	run lib::os::cache_home libsh

	assert_output "$HOME/.cache/libsh"
}

@test "lib::os::cache_home falls back to ~/Library/Caches on Darwin" {
	fake_uname_darwin

	run lib::os::cache_home

	assert_output "$HOME/Library/Caches"
}

@test "lib::os::cache_home nests an app name under the Darwin base directory" {
	fake_uname_darwin

	run lib::os::cache_home libsh

	assert_output "$HOME/Library/Caches/libsh"
}

@test "lib::os::cache_home still honours XDG_CACHE_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CACHE_HOME="$TEST_TMP/custom-cache"

	run lib::os::cache_home

	assert_output "$TEST_TMP/custom-cache"
}

@test 'lib::os::state_home falls back to $HOME/.local/state' {
	run lib::os::state_home

	assert_output "$HOME/.local/state"
}

@test "lib::os::state_home honours XDG_STATE_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_STATE_HOME="$TEST_TMP/custom-state"

	run lib::os::state_home

	assert_output "$TEST_TMP/custom-state"
}

@test "lib::os::state_home nests an app name under the base directory" {
	run lib::os::state_home libsh

	assert_output "$HOME/.local/state/libsh"
}

@test "lib::os::state_home falls back to ~/Library on Darwin with no app name" {
	fake_uname_darwin

	run lib::os::state_home

	assert_output "$HOME/Library"
}

# Extrapolated from data_home's own Darwin shape -- gopskit has no State
# concept of its own to mirror here.
@test "lib::os::state_home nests as <app>/State on Darwin" {
	fake_uname_darwin

	run lib::os::state_home libsh

	assert_output "$HOME/Library/libsh/State"
}

@test "lib::os::state_home still honours XDG_STATE_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_STATE_HOME="$TEST_TMP/custom-state"

	run lib::os::state_home libsh

	assert_output "$TEST_TMP/custom-state/libsh"
}

# lib::os::is_executable
@test "lib::os::is_executable succeeds for a binary on PATH" {
	run lib::os::is_executable bash

	assert_success
}

@test "lib::os::is_executable succeeds for a shell builtin" {
	run lib::os::is_executable cd

	assert_success
}

@test "lib::os::is_executable fails for a missing binary" {
	run lib::os::is_executable definitely-not-a-real-binary

	assert_failure
}

# An unset argument must not read as "found": every prerequisite check in
# scripts/ depends on this failing closed.
@test "lib::os::is_executable fails for an empty argument" {
	run lib::os::is_executable ""

	assert_failure
}

# lib::os::root_check -- EUID is read-only in bash, so the test
# asserts against whoever is actually running it.
@test "lib::os::root_check reflects the current user" {
	run lib::os::root_check

	if [[ $EUID -eq 0 ]]; then
		assert_success
	else
		assert_failure
	fi
}

# lib::os::root_exec
@test "lib::os::root_exec delegates to sudo when not root" {
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

	PATH="$TEST_TMP:$PATH" run lib::os::root_exec apt-get update

	assert_output "sudo called with: apt-get update"
}

@test "lib::os::root_exec runs the command directly when root" {
	if [[ $EUID -ne 0 ]]; then
		skip "not root: the direct path is unreachable"
	fi

	run lib::os::root_exec echo "ran directly"

	assert_output "ran directly"
}

@test "lib::os::root_exec passes arguments through unsplit" {
	if [[ $EUID -eq 0 ]]; then
		skip "already root: the sudo path is unreachable"
	fi

	cat >"$TEST_TMP/sudo" <<-'FAKE'
		#!/usr/bin/env bash
		for arg in "$@"; do printf '[%s]\n' "$arg"; done
	FAKE
	chmod +x "$TEST_TMP/sudo"

	PATH="$TEST_TMP:$PATH" run lib::os::root_exec cp -- "a file" "another file"

	assert_output "[cp]
[--]
[a file]
[another file]"
}

@test "lib::os::root_exec propagates the command's exit code" {
	if [[ $EUID -eq 0 ]]; then
		skip "already root: the sudo path is unreachable"
	fi

	printf '#!/usr/bin/env bash\nexit 7\n' >"$TEST_TMP/sudo"
	chmod +x "$TEST_TMP/sudo"

	PATH="$TEST_TMP:$PATH" run lib::os::root_exec false

	assert_failure 7
}

# lib::os::rc
@test "lib::os::rc sources an existing .bashrc" {
	printf 'LIBSH_RC_MARKER=bashrc\n' >"$HOME/.bashrc"

	lib::os::rc

	assert_equal "${LIBSH_RC_MARKER:-}" "bashrc"
}

@test "lib::os::rc does not source Zsh configuration into Bash" {
	printf 'LIBSH_ZSH_MARKER=zshrc\n' >"$HOME/.zshrc"

	lib::os::rc

	assert_equal "${LIBSH_ZSH_MARKER:-}" ""
}

@test "lib::os::rc succeeds when neither rc file exists" {
	run lib::os::rc

	assert_success
}

teardown() {
	cd "$ORIGINAL_PWD" || return 1
	export HOME="$ORIGINAL_HOME" PATH="$ORIGINAL_PATH"
	if [[ -n ${TEST_TMP:-} ]]; then rm -rf "$TEST_TMP"; fi
}

@test "executable lookup preserves caller variables and produces no stdout" {
	command_package=sentinel
	local captured
	captured=$(lib::os::is_executable bash)
	assert_equal "$captured" ''
	lib::os::is_executable bash
	assert_equal "$command_package" sentinel
}

@test "rc propagates Bash configuration failures" {
	printf 'return 17\n' >"$HOME/.bashrc"
	run lib::os::rc
	assert_failure 17
}
