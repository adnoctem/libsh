#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # BATS isolates test configuration in subshells

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

  source "$REPO_ROOT/lib/lib.sh"
  unset LIBSH_DEBUG NO_COLOR
  export TERM=dumb
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

@test "intent emitters label literal messages and route each stream without redirected color" {
  # shellcheck disable=SC2329 # deterministic timestamp fixture
  date() { printf '2026-09-13T12:30:00Z\n'; }
  local intent destination message=$'--100% C:\\bin\nnext\n'
  export LIBSH_DEBUG=true TERM=xterm

  for intent in info success notice debug warn error; do
    "lib::log::print_$intent" "$message" >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err"
    case $intent in
      info | success | notice)
        destination=out
        [[ ! -s $BATS_TEST_TMPDIR/err ]]
        ;;
      *)
        destination=err
        [[ ! -s $BATS_TEST_TMPDIR/out ]]
        ;;
    esac

    printf '[2026-09-13T12:30:00Z] %s: %s\n' "${intent^^}" "$message" >"$BATS_TEST_TMPDIR/expected"
    cmp "$BATS_TEST_TMPDIR/$destination" "$BATS_TEST_TMPDIR/expected"
    "lib::log::write_$intent" "$BATS_TEST_TMPDIR/$intent" "$message"
    "lib::log::write_$intent" "$BATS_TEST_TMPDIR/$intent" ''
    printf '[2026-09-13T12:30:00Z] %s: \n' "${intent^^}" >>"$BATS_TEST_TMPDIR/expected"
    cmp "$BATS_TEST_TMPDIR/$intent" "$BATS_TEST_TMPDIR/expected"
  done
}

@test "debug enablement is dynamic and accepts only true or one" {
  local value
  run lib::log::debug_enabled
  assert_failure 1
  run lib::log::debug_enabled unexpected
  assert_failure 2

  for value in '' 0 false TRUEE yes 2; do
    LIBSH_DEBUG=$value run lib::log::debug_enabled
    assert_failure 1
    LIBSH_DEBUG=$value run lib::log::print_debug ignored
    assert_success
    assert_output ''
  done

  for value in 1 true TRUE tRuE; do
    LIBSH_DEBUG=$value run lib::log::debug_enabled
    assert_success
    LIBSH_DEBUG=$value run lib::log::print_debug enabled
    assert_success
    assert_output --partial 'DEBUG: enabled'
  done
  [[ ! ${LIBSH_DEBUG+set} ]]
}

@test "disabled debug skips validation backend work and file access under strict mode" {
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    unset LIBSH_DEBUG
    function lib::os::date() { printf called >"$2"; return 1; }
    function __libsh_log_print() { exit 90; }
    function __libsh_log_write() { exit 91; }
    lib::log::print_debug 2>&-
    lib::log::print_debug too many arguments 2>&-
    lib::log::write_debug "$2" message 2>&-
    lib::log::write_debug 2>&-
  ' _ "$REPO_ROOT" "$BATS_TEST_TMPDIR/unexpected"
  assert_success
  assert_output ''
  [[ ! -e $BATS_TEST_TMPDIR/unexpected ]]
}

@test "active intent emitters validate arguments before timestamp work" {
  # shellcheck disable=SC2329 # timestamp sentinel
  date() { touch "$BATS_TEST_TMPDIR/unexpected"; }
  export LIBSH_DEBUG=1
  local intent

  for intent in info success notice debug warn error; do
    run "lib::log::print_$intent"
    assert_failure 2
    run "lib::log::print_$intent" one two
    assert_failure 2
    run "lib::log::write_$intent" '' message
    assert_failure 2
    run "lib::log::write_$intent" "$BATS_TEST_TMPDIR/log"
    assert_failure 2
    run "lib::log::write_$intent" "$BATS_TEST_TMPDIR/log" message extra
    assert_failure 2
  done
  [[ ! -e $BATS_TEST_TMPDIR/unexpected && ! -e $BATS_TEST_TMPDIR/log ]]
}

@test "intent timestamp failures produce no partial records or files" {
  # shellcheck disable=SC2329 # failing backend
  date() {
    printf partial
    return 9
  }
  export LIBSH_DEBUG=true
  local intent

  for intent in info success notice debug warn error; do
    run "lib::log::print_$intent" rejected
    assert_failure 1
    assert_output ''
    run "lib::log::write_$intent" "$BATS_TEST_TMPDIR/log" rejected
    assert_failure 1
    assert_output ''
  done
  [[ ! -e $BATS_TEST_TMPDIR/log ]]
}

@test "intent printing propagates closed descriptor failures" {
  local intent
  export LIBSH_DEBUG=true

  for intent in info success notice debug warn error; do
    run bash -c 'source "$1/lib/lib.sh"; "$2" message >&- 2>&-' _ "$REPO_ROOT" "lib::log::print_$intent"
    assert_failure 1
  done
}

@test "intent file writes reject nonregular destinations and preserve existing files on timestamp failure" {
  local file="$BATS_TEST_TMPDIR/log"
  printf original >"$file"

  run lib::log::write_success "$BATS_TEST_TMPDIR" rejected
  assert_failure 1
  run lib::log::write_notice "$BATS_TEST_TMPDIR/missing/log" rejected
  assert_failure 1
  mkfifo "$BATS_TEST_TMPDIR/fifo"
  run lib::log::write_error "$BATS_TEST_TMPDIR/fifo" rejected
  assert_failure 1

  # shellcheck disable=SC2329
  date() { return 7; }
  run lib::log::write_warn "$file" rejected
  assert_failure 1
  assert_equal "$(cat "$file")" original
}

@test "intent logging preserves strict caller state and configuration" {
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    trap ":" USR1
    LIBSH_DEBUG=true
    NO_COLOR=1
    OPTS=(sentinel)
    declare -A OPTS_VALUES=([sentinel]=value)
    before=$(set +o; trap -p; pwd; umask; declare -p OPTS OPTS_VALUES LIBSH_DEBUG NO_COLOR)
    lib::log::print_debug "enabled"
    lib::log::write_success "$2/log" "complete"
    after=$(set +o; trap -p; pwd; umask; declare -p OPTS OPTS_VALUES LIBSH_DEBUG NO_COLOR)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT" "$BATS_TEST_TMPDIR"
  assert_success
  assert_output --partial 'DEBUG: enabled'
}

@test "terminal intent colors match the palette and respect destination and opt-outs" {
  command -v script >/dev/null || skip 'script is required for pseudo-terminal coverage'
  local driver="$BATS_TEST_TMPDIR/terminal.sh"
  cat >"$driver" <<'DRIVER'
#!/usr/bin/env bash
source "$REPO_ROOT/lib/lib.sh"
function lib::os::date() { printf '2026-09-13T12:30:00Z\n'; }
export LIBSH_DEBUG=1 TERM=xterm
unset NO_COLOR
for intent in info success notice debug warn error; do
  "lib::log::print_$intent" message
done
NO_COLOR=1 lib::log::print_success no-color
TERM=dumb lib::log::print_warn dumb
lib::log::print_error redirected 2>"$LIBSH_LOG_TEST_OUTPUT"
lib::log::print_info redirected >>"$LIBSH_LOG_TEST_OUTPUT"
DRIVER
  export REPO_ROOT LIBSH_LOG_TEST_SCRIPT="$driver" LIBSH_LOG_TEST_OUTPUT="$BATS_TEST_TMPDIR/redirected"

  if [[ $(uname -s) == Darwin ]]; then
    run script -q /dev/null bash "$driver"
  else
    # shellcheck disable=SC2016 # expanded by the shell inside the pseudo-terminal
    run script -q -e -c 'bash "$LIBSH_LOG_TEST_SCRIPT"' /dev/null
  fi
  assert_success
  local intent color
  for intent in info success notice debug warn error; do
    case $intent in
      info) color=37 ;;
      success) color=32 ;;
      notice | warn) color=33 ;;
      debug) color=36 ;;
      error) color=31 ;;
    esac
    assert_output --partial "$(printf '[2026-09-13T12:30:00Z] \033[1;%sm%s\033[0m: message' "$color" "${intent^^}")"
  done
  assert_output --partial '[2026-09-13T12:30:00Z] SUCCESS: no-color'
  assert_output --partial '[2026-09-13T12:30:00Z] WARN: dumb'
  assert_equal "$(cat "$LIBSH_LOG_TEST_OUTPUT")" $'[2026-09-13T12:30:00Z] ERROR: redirected\n[2026-09-13T12:30:00Z] INFO: redirected'
}
