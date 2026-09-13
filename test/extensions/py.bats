#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions py

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

# ext::py::venv
@test "ext::py::venv activates an existing venv" {
  mkdir -p "$TEST_TMP/project/.venv/bin"
  printf 'LIBSH_VENV_MARKER=activated\n' >"$TEST_TMP/project/.venv/bin/activate"
  cd "$TEST_TMP/project" || return 1

  ext::py::venv

  assert_equal "${LIBSH_VENV_MARKER:-}" "activated"
}

# The venv path used to be written as "(pwd)/.venv" without the '$', which
# created a directory literally named '(pwd)' in the working directory.
@test "ext::py::venv creates the venv in the working directory" {
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
  # shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
  export PATH="$TEST_TMP/bin:$PATH"
  cd "$TEST_TMP/fresh" || return 1

  ext::py::venv

  assert_equal "$(cat "$FAKE_VENV_LOG")" "$TEST_TMP/fresh/.venv"
  refute [ -e "$TEST_TMP/fresh/(pwd)" ]
}

@test "ext::py::venv activates the venv it just created" {
  mkdir -p "$TEST_TMP/fresh2" "$TEST_TMP/bin"

  cat >"$TEST_TMP/bin/python3" <<-'FAKE'
		#!/usr/bin/env bash
		mkdir -p "$3/bin"
		printf 'LIBSH_VENV_MARKER=created\n' >"$3/bin/activate"
	FAKE
  chmod +x "$TEST_TMP/bin/python3"

  # shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
  export PATH="$TEST_TMP/bin:$PATH"
  cd "$TEST_TMP/fresh2" || return 1

  ext::py::venv

  assert_equal "${LIBSH_VENV_MARKER:-}" "created"
}

@test "ext::py::venv reports a failure from python" {
  mkdir -p "$TEST_TMP/fresh3" "$TEST_TMP/bin"

  printf '#!/usr/bin/env bash\nexit 4\n' >"$TEST_TMP/bin/python3"
  chmod +x "$TEST_TMP/bin/python3"

  # shellcheck disable=SC2030,SC2031 # each bats @test runs in its own process; this scoping is intentional
  export PATH="$TEST_TMP/bin:$PATH"
  cd "$TEST_TMP/fresh3" || return 1

  run ext::py::venv

  assert_failure 4
}

@test "venv accepts an explicit path and creation interpreter" {
  # shellcheck disable=SC2329 # creation fixture
  custom_python() {
    [[ $1 == -m && $2 == venv && $3 == "$TEST_TMP/custom env" ]] || return 9
    mkdir -p "$3/bin"
    printf 'LIBSH_CUSTOM_VENV=activated\n' >"$3/bin/activate"
  }
  ext::py::venv "$TEST_TMP/custom env" --python custom_python
  assert_equal "${LIBSH_CUSTOM_VENV:-}" activated
}

@test "venv refuses incomplete existing paths and reports activation failure" {
  mkdir "$TEST_TMP/incomplete"
  run ext::py::venv "$TEST_TMP/incomplete"
  assert_failure 1
  [[ ! -e $TEST_TMP/incomplete/bin ]]
  mkdir -p "$TEST_TMP/incomplete/bin"
  printf 'return 7\n' >"$TEST_TMP/incomplete/bin/activate"
  run ext::py::venv "$TEST_TMP/incomplete"
  assert_failure 7
  run ext::py::venv "$TEST_TMP/new" --python ''
  assert_failure 2
}
