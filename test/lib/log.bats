#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

  source "$REPO_ROOT/lib/lib.sh"
}

# lib::log::print
@test "lib::log::print wraps the message in the given color" {
  run lib::log::print "31m" "boom"

  assert_output "$(printf '\033[1;31mboom\033[0m')"
}

# The message is data: a backslash in a path, a pattern or a password must
# survive verbatim. This is why the module uses printf and not 'echo -e'.
@test "lib::log::print does not interpret escapes in the message" {
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

@test "file logging preserves message bytes and appends exactly one newline per call" {
  local file="$BATS_TEST_TMPDIR/log file" value=$'100% C:\\bin\\new\n\n'

  run lib::log::write "$file" "$value"
  assert_success
  assert_output ''
  lib::log::write "$file" ''
  lib::log::write "$file" --help

  printf '%s\n\n%s\n' "$value" --help >"$BATS_TEST_TMPDIR/expected"
  cmp "$file" "$BATS_TEST_TMPDIR/expected"
}

@test "file logging timestamps only when requested and fails before writing if date fails" {
  local file="$BATS_TEST_TMPDIR/log"

  # shellcheck disable=SC2329 # called by lib::log::write
  date() {
    [[ $* == '-u +%Y-%m-%dT%H:%M:%SZ' ]] || return 9
    printf '2026-09-13T12:30:00Z\n'
  }

  lib::log::write "$file" entry --timestamp
  assert_equal "$(cat "$file")" '[2026-09-13T12:30:00Z] entry'

  # shellcheck disable=SC2329
  date() { return 7; }

  run lib::log::write "$file" rejected --timestamp
  assert_failure 1
  assert_equal "$(cat "$file")" '[2026-09-13T12:30:00Z] entry'
  lib::log::write "$file" plain
  assert_equal "$(tail -n 1 "$file")" plain
}

@test "file logging rejects invalid calls missing parents and nonregular destinations" {
  run lib::log::write
  assert_failure 2
  run lib::log::write '' message
  assert_failure 2
  run lib::log::write "$BATS_TEST_TMPDIR/log" message --unknown
  assert_failure 2
  [[ ! -e $BATS_TEST_TMPDIR/log ]]

  run lib::log::write "$BATS_TEST_TMPDIR/missing/log" message
  assert_failure 1
  run lib::log::write "$BATS_TEST_TMPDIR" message
  assert_failure 1
  mkfifo "$BATS_TEST_TMPDIR/fifo"
  run lib::log::write "$BATS_TEST_TMPDIR/fifo" message
  assert_failure 1
  ln -s missing "$BATS_TEST_TMPDIR/broken"
  run lib::log::write "$BATS_TEST_TMPDIR/broken" message
  assert_failure 1
}

@test "file logging follows existing file symlinks and preserves strict caller state" {
  : >"$BATS_TEST_TMPDIR/real"
  ln -s real "$BATS_TEST_TMPDIR/link"

  run bash -c '
    set -euo pipefail
    source "$1/lib/lib.sh"
    trap ":" USR1
    before=$(set +o); traps=$(trap -p); mask=$(umask); directory=$PWD
    lib::log::write "$2/link" "entry"
    [[ $(set +o) == "$before" && $(trap -p) == "$traps" ]]
    [[ $(umask) == "$mask" && $PWD == "$directory" ]]
  ' _ "$REPO_ROOT" "$BATS_TEST_TMPDIR"
  assert_success
  assert_equal "$(cat "$BATS_TEST_TMPDIR/real")" entry
  [[ -L $BATS_TEST_TMPDIR/link ]]
}

@test "file logging propagates failed appends" {
  if [[ $EUID == 0 ]]; then skip 'effective root access bypasses ordinary permissions'; fi
  local file="$BATS_TEST_TMPDIR/readonly"
  printf original >"$file"
  chmod 400 "$file"

  run lib::log::write "$file" rejected
  assert_failure 1
  assert_equal "$(cat "$file")" original
}
