#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/utils.sh"

	TEST_TMP=$(mktemp -d)

	# Both functions read $HOME or $PWD and source what they find, so every
	# test runs against a scratch home and a scratch working directory
	# rather than the developer's real dotfiles.
	ORIGINAL_HOME="$HOME"
	ORIGINAL_PWD="$PWD"
	export HOME="$TEST_TMP/home"
	mkdir -p "$HOME"
}

teardown() {
	cd "$ORIGINAL_PWD" || true
	export HOME="$ORIGINAL_HOME"
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# lib::utils::rc
@test "lib::utils::rc sources an existing .bashrc" {
	printf 'LIBSH_RC_MARKER=bashrc\n' >"$HOME/.bashrc"

	lib::utils::rc

	assert_equal "${LIBSH_RC_MARKER:-}" "bashrc"
}

@test "lib::utils::rc sources an existing .zshrc" {
	printf 'LIBSH_ZSH_MARKER=zshrc\n' >"$HOME/.zshrc"

	lib::utils::rc

	assert_equal "${LIBSH_ZSH_MARKER:-}" "zshrc"
}

@test "lib::utils::rc succeeds when neither rc file exists" {
	run lib::utils::rc

	assert_success
}

# lib::utils::venv
@test "lib::utils::venv activates an existing venv" {
	mkdir -p "$TEST_TMP/project/.venv/bin"
	printf 'LIBSH_VENV_MARKER=activated\n' >"$TEST_TMP/project/.venv/bin/activate"
	cd "$TEST_TMP/project" || return 1

	lib::utils::venv

	assert_equal "${LIBSH_VENV_MARKER:-}" "activated"
}

# The venv path used to be written as "(pwd)/.venv" without the '$', which
# created a directory literally named '(pwd)' in the working directory.
@test "lib::utils::venv creates the venv in the working directory" {
	mkdir -p "$TEST_TMP/fresh" "$TEST_TMP/bin"

	cat >"$TEST_TMP/bin/python3" <<-'FAKE'
		#!/usr/bin/env bash
		# stand-in for 'python3 -m venv <path>': record the path, make it usable
		printf '%s\n' "$3" >"$FAKE_VENV_LOG"
		mkdir -p "$3/bin"
		printf 'LIBSH_VENV_MARKER=created\n' >"$3/bin/activate"
	FAKE
	chmod +x "$TEST_TMP/bin/python3"

	export FAKE_VENV_LOG="$TEST_TMP/venv-path.log"
	export PATH="$TEST_TMP/bin:$PATH"
	cd "$TEST_TMP/fresh" || return 1

	lib::utils::venv

	assert_equal "$(cat "$FAKE_VENV_LOG")" "$TEST_TMP/fresh/.venv"
	refute [ -e "$TEST_TMP/fresh/(pwd)" ]
}

@test "lib::utils::venv activates the venv it just created" {
	mkdir -p "$TEST_TMP/fresh2" "$TEST_TMP/bin"

	cat >"$TEST_TMP/bin/python3" <<-'FAKE'
		#!/usr/bin/env bash
		mkdir -p "$3/bin"
		printf 'LIBSH_VENV_MARKER=created\n' >"$3/bin/activate"
	FAKE
	chmod +x "$TEST_TMP/bin/python3"

	export PATH="$TEST_TMP/bin:$PATH"
	cd "$TEST_TMP/fresh2" || return 1

	lib::utils::venv

	assert_equal "${LIBSH_VENV_MARKER:-}" "created"
}

@test "lib::utils::venv reports a failure from python" {
	mkdir -p "$TEST_TMP/fresh3" "$TEST_TMP/bin"

	printf '#!/usr/bin/env bash\nexit 4\n' >"$TEST_TMP/bin/python3"
	chmod +x "$TEST_TMP/bin/python3"

	export PATH="$TEST_TMP/bin:$PATH"
	cd "$TEST_TMP/fresh3" || return 1

	run lib::utils::venv

	assert_failure 4
}
