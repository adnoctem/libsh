#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/paths.sh"

	TEST_TMP=$(mktemp -d)
	ORIGINAL_HOME="$HOME"
	export HOME="$TEST_TMP/home"
	mkdir -p "$HOME"

	ORIGINAL_PATH="$PATH"
	mkdir -p "$TEST_TMP/bin"
	export PATH="$TEST_TMP/bin:$PATH"

	# Never let the real environment's XDG_* vars leak into a test that
	# means to exercise the spec's own fallback defaults.
	unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
}

teardown() {
	export HOME="$ORIGINAL_HOME"
	export PATH="$ORIGINAL_PATH"
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
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

# lib::paths::config_home / data_home / cache_home / state_home -- the XDG
# Base Directory Specification's four user directories, each honouring its
# XDG_*_HOME override with the spec's documented fallback.
@test 'lib::paths::config_home falls back to $HOME/.config' {
	run lib::paths::config_home

	assert_output "$HOME/.config"
}

@test "lib::paths::config_home honours XDG_CONFIG_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CONFIG_HOME="$TEST_TMP/custom-config"

	run lib::paths::config_home

	assert_output "$TEST_TMP/custom-config"
}

@test "lib::paths::config_home nests an app name under the base directory" {
	run lib::paths::config_home libsh

	assert_output "$HOME/.config/libsh"
}

@test "lib::paths::config_home falls back to ~/Library/Application Support on Darwin" {
	fake_uname_darwin

	run lib::paths::config_home

	assert_output "$HOME/Library/Application Support"
}

@test "lib::paths::config_home nests an app name under the Darwin base directory" {
	fake_uname_darwin

	run lib::paths::config_home libsh

	assert_output "$HOME/Library/Application Support/libsh"
}

@test "lib::paths::config_home still honours XDG_CONFIG_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CONFIG_HOME="$TEST_TMP/custom-config"

	run lib::paths::config_home

	assert_output "$TEST_TMP/custom-config"
}

@test 'lib::paths::data_home falls back to $HOME/.local/share' {
	run lib::paths::data_home

	assert_output "$HOME/.local/share"
}

@test "lib::paths::data_home honours XDG_DATA_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_DATA_HOME="$TEST_TMP/custom-data"

	run lib::paths::data_home

	assert_output "$TEST_TMP/custom-data"
}

@test "lib::paths::data_home nests an app name under the base directory" {
	run lib::paths::data_home libsh

	assert_output "$HOME/.local/share/libsh"
}

@test "lib::paths::data_home falls back to ~/Library on Darwin with no app name" {
	fake_uname_darwin

	run lib::paths::data_home

	assert_output "$HOME/Library"
}

# Darwin nests the app name before a fixed 'Data' leaf (~/Library/<app>/Data),
# the reverse of config/cache's app-last shape -- matches gopskit's own
# paths_darwin.go, not smoothed over to look consistent with the others.
@test "lib::paths::data_home nests as <app>/Data on Darwin" {
	fake_uname_darwin

	run lib::paths::data_home libsh

	assert_output "$HOME/Library/libsh/Data"
}

@test "lib::paths::data_home still honours XDG_DATA_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_DATA_HOME="$TEST_TMP/custom-data"

	run lib::paths::data_home libsh

	assert_output "$TEST_TMP/custom-data/libsh"
}

@test 'lib::paths::cache_home falls back to $HOME/.cache' {
	run lib::paths::cache_home

	assert_output "$HOME/.cache"
}

@test "lib::paths::cache_home honours XDG_CACHE_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CACHE_HOME="$TEST_TMP/custom-cache"

	run lib::paths::cache_home

	assert_output "$TEST_TMP/custom-cache"
}

@test "lib::paths::cache_home nests an app name under the base directory" {
	run lib::paths::cache_home libsh

	assert_output "$HOME/.cache/libsh"
}

@test "lib::paths::cache_home falls back to ~/Library/Caches on Darwin" {
	fake_uname_darwin

	run lib::paths::cache_home

	assert_output "$HOME/Library/Caches"
}

@test "lib::paths::cache_home nests an app name under the Darwin base directory" {
	fake_uname_darwin

	run lib::paths::cache_home libsh

	assert_output "$HOME/Library/Caches/libsh"
}

@test "lib::paths::cache_home still honours XDG_CACHE_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_CACHE_HOME="$TEST_TMP/custom-cache"

	run lib::paths::cache_home

	assert_output "$TEST_TMP/custom-cache"
}

@test 'lib::paths::state_home falls back to $HOME/.local/state' {
	run lib::paths::state_home

	assert_output "$HOME/.local/state"
}

@test "lib::paths::state_home honours XDG_STATE_HOME" {
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_STATE_HOME="$TEST_TMP/custom-state"

	run lib::paths::state_home

	assert_output "$TEST_TMP/custom-state"
}

@test "lib::paths::state_home nests an app name under the base directory" {
	run lib::paths::state_home libsh

	assert_output "$HOME/.local/state/libsh"
}

@test "lib::paths::state_home falls back to ~/Library on Darwin with no app name" {
	fake_uname_darwin

	run lib::paths::state_home

	assert_output "$HOME/Library"
}

# Extrapolated from data_home's own Darwin shape -- gopskit has no State
# concept of its own to mirror here.
@test "lib::paths::state_home nests as <app>/State on Darwin" {
	fake_uname_darwin

	run lib::paths::state_home libsh

	assert_output "$HOME/Library/libsh/State"
}

@test "lib::paths::state_home still honours XDG_STATE_HOME on Darwin" {
	fake_uname_darwin
	# shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
	export XDG_STATE_HOME="$TEST_TMP/custom-state"

	run lib::paths::state_home libsh

	assert_output "$TEST_TMP/custom-state/libsh"
}
