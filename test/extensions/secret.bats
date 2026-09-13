#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(git rev-parse --show-toplevel)}

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions secret

  TEST_TMP=$(mktemp -d)
  SECRET_FILE="$TEST_TMP/password"
  printf 'p@ss:w/rd!#100%%\n' >"$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
}

teardown() {
  [[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# ext::secret::from_file
@test "ext::secret::from_file returns the secret verbatim" {
  run ext::secret::from_file "$SECRET_FILE"

  assert_success
  assert_output 'p@ss:w/rd!#100%'
}

# The trailing newline is an editor artifact, not part of the password.
@test "ext::secret::from_file reads only the first line" {
  printf 'first-line\nsecond-line\n' >"$SECRET_FILE"

  run ext::secret::from_file "$SECRET_FILE"

  assert_output "first-line"
}

@test "ext::secret::from_file handles a file with no trailing newline" {
  printf 'no-newline-here' >"$SECRET_FILE"

  run ext::secret::from_file "$SECRET_FILE"

  assert_success
  assert_output "no-newline-here"
}

# Callers capture stdout with a command substitution, so a warning that
# lands there would be captured as part of the password.
@test "ext::secret::from_file keeps warnings off stdout" {
  chmod 644 "$SECRET_FILE"

  local captured
  captured=$(ext::secret::from_file "$SECRET_FILE" 2>/dev/null)

  assert_equal "$captured" 'p@ss:w/rd!#100%'
}

@test "ext::secret::from_file warns about world-readable permissions" {
  chmod 644 "$SECRET_FILE"

  local warning
  warning=$(ext::secret::from_file "$SECRET_FILE" 2>&1 1>/dev/null)

  [[ $warning == *"mode 644"* ]]
}

@test "ext::secret::from_file stays quiet for a 600 file" {
  local warning
  warning=$(ext::secret::from_file "$SECRET_FILE" 2>&1 1>/dev/null)

  assert_equal "$warning" ""
}

@test "ext::secret::from_file fails on a missing file" {
  run ext::secret::from_file "$TEST_TMP/does-not-exist"

  assert_failure
  assert_output --partial "does not exist"
}

@test "ext::secret::from_file fails on an empty file" {
  : >"$SECRET_FILE"

  run ext::secret::from_file "$SECRET_FILE"

  assert_failure
  assert_output --partial "is empty"
}

@test "ext::secret::from_file fails on a file it cannot read" {
  chmod 000 "$SECRET_FILE"

  run ext::secret::from_file "$SECRET_FILE"

  # root can read anything, so the unreadable case cannot be provoked there.
  if [[ $EUID -eq 0 ]]; then
    skip "running as root: permissions do not apply"
  fi

  assert_failure
  assert_output --partial "not readable"
}

@test "text reader preserves exact bytes and caller-local names" {
  local path='' value='' secret='' text
  for text in $'-----BEGIN CERTIFICATE-----\nABC\\123\n-----END CERTIFICATE-----\n\n' \
    $' \t\"quoted\" \'text\' \\ café\n\n\n' '000123' 'false' 'no newline'; do
    printf '%s' "$text" >"$SECRET_FILE"
    ext::secret::read_file path "$SECRET_FILE"
    ext::secret::read_file value "$SECRET_FILE"
    ext::secret::read_file secret "$SECRET_FILE"
    [[ $path == "$text" && $value == "$text" && $secret == "$text" ]]
    printf '%s' "$value" >"$TEST_TMP/actual"
    cmp "$SECRET_FILE" "$TEST_TMP/actual"
  done
}

@test "new reader distinguishes text, first-line and empty policies" {
  local result=old
  printf '\nsecond\n' >"$SECRET_FILE"
  ext::secret::read_file result "$SECRET_FILE"
  [[ $result == $'\nsecond\n' ]]
  if ext::secret::read_file result "$SECRET_FILE" --mode first-line; then return 1; fi
  [[ $result == $'\nsecond\n' ]]
  ext::secret::read_file result "$SECRET_FILE" --mode first-line --allow-empty
  [[ $result == '' ]]
  : >"$SECRET_FILE"
  if ext::secret::read_file result "$SECRET_FILE"; then return 1; fi
  ext::secret::read_file result "$SECRET_FILE" --allow-empty
  [[ $result == '' ]]
}

@test "new reader rejects NUL anywhere without assignment in either mode" {
  local result=unchanged bytes mode
  for bytes in '\000before' 'mid\000dle' 'after\000' 'first\nsecond\000'; do
    printf '%b' "$bytes" >"$SECRET_FILE"
    for mode in text first-line; do
      if ext::secret::read_file result "$SECRET_FILE" --mode "$mode"; then return 1; fi
      [[ $result == unchanged ]]
    done
  done
}

@test "new reader follows projected-style symlinks without permission warnings" {
  mkdir "$TEST_TMP/..version"
  printf 'mounted\n\n' >"$TEST_TMP/..version/key"
  chmod 640 "$TEST_TMP/..version/key"
  ln -s ..version "$TEST_TMP/..data"
  ln -s ..data/key "$TEST_TMP/key"
  local result=''
  ext::secret::read_file result "$TEST_TMP/key" >"$TEST_TMP/out" 2>"$TEST_TMP/err"
  [[ $result == $'mounted\n\n' && ! -s $TEST_TMP/out && ! -s $TEST_TMP/err ]]
}

@test "new reader rejects non-files, unreadable files and partial reader errors" {
  local result=unchanged item
  mkfifo "$TEST_TMP/fifo"
  ln -s missing "$TEST_TMP/dangling"
  for item in "$TEST_TMP" "$TEST_TMP/missing" "$TEST_TMP/fifo" "$TEST_TMP/dangling"; do
    if ext::secret::read_file result "$item"; then return 1; fi
    [[ $result == unchanged ]]
  done
  if [[ $EUID != 0 ]]; then
    chmod 000 "$SECRET_FILE"
    if ext::secret::read_file result "$SECRET_FILE"; then return 1; fi
    chmod 600 "$SECRET_FILE"
  fi
  od() {
    printf ' 141 142\n'
    printf 'synthetic-reader-detail' >&2
    return 1
  }
  if ext::secret::read_file result "$SECRET_FILE" 2>"$TEST_TMP/err"; then return 1; fi
  [[ $result == unchanged ]]
  [[ $(cat "$TEST_TMP/err") != *synthetic-reader-detail* ]]
}

@test "secret reader keeps bytes and paths out of external argv and diagnostics" {
  local result='' synthetic=$'synthetic-secret-000123\n\n'
  printf '%s' "$synthetic" >"$SECRET_FILE"
  mkdir "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/od" <<-FAKE
		#!/usr/bin/env bash
		printf '%s\n' "\$@" >"$TEST_TMP/argv"
		exec /usr/bin/od "\$@"
	FAKE
  chmod +x "$TEST_TMP/bin/od"
  PATH="$TEST_TMP/bin:$PATH" ext::secret::read_file result "$SECRET_FILE" >"$TEST_TMP/out" 2>"$TEST_TMP/err"
  [[ $result == "$synthetic" && ! -s $TEST_TMP/out && ! -s $TEST_TMP/err ]]
  run grep -F -e synthetic-secret -e "$SECRET_FILE" "$TEST_TMP/argv"
  assert_failure 1
  PATH="$TEST_TMP/bin" run ext::secret::read_file result "$SECRET_FILE"
  # An existing but unexecutable reader must also return cleanly.
  assert_failure 1
}

@test "output references reject attributes, expressions, reserved names and collisions" {
  local result=unchanged name
  local -i integer=12
  local -a indexed=(old)
  local -A associative=([key]=old)
  local -r fixed=old
  # shellcheck disable=SC2016 # deliberately reject a literal shell expression, without evaluating it
  for name in 'x[0]' 'x[$(false)]' 'a-b' '__libsh_read_path' IFS PATH RANDOM integer indexed associative fixed; do
    run ext::secret::read_file "$name" "$SECRET_FILE"
    assert_failure 2
  done
  if [[ ${BASH_VERSINFO[0]} -gt 4 || ${BASH_VERSINFO[1]} -ge 3 ]]; then
    local -n alias=result
    run ext::secret::read_file alias "$SECRET_FILE"
    assert_failure 2
    [[ $alias == unchanged ]]
  fi
  local -u upper=old
  local -l lower=OLD
  for name in upper lower; do
    run ext::secret::read_file "$name" "$SECRET_FILE"
    assert_failure 2
  done
  [[ $result == unchanged && $integer == 12 && $fixed == old ]]
  [[ ${indexed[0]} == old && ${associative[key]} == old && $upper == OLD && $lower == old ]]
}

@test "resolver selects presence before files and preserves output on empty error" {
  local direct='' file="$TEST_TMP/missing" result=old
  if ext::secret::resolve result --value-var direct --file-var file; then return 1; fi
  [[ $result == old ]]
  ext::secret::resolve result --value-var direct --file-var file --allow-empty
  [[ $result == '' ]]
  direct=$'000123\n\n'
  ext::secret::resolve result --value-var direct --file-var file --mode first-line
  [[ $result == "$direct" ]]
  ext::secret::resolve direct --value-var direct --file-var file
  [[ $direct == $'000123\n\n' ]]
}

@test "resolver uses files and explicit legacy precedence, and unsets absent output" {
  local direct file="$SECRET_FILE" result=old
  printf 'first\nlast\n\n' >"$SECRET_FILE"
  ext::secret::resolve result --value-var direct --file-var file
  [[ $result == $'first\nlast\n\n' ]]
  direct=''
  ext::secret::resolve result --value-var direct --file-var file --precedence nonempty --mode first-line
  [[ $result == first ]]
  unset file
  ext::secret::resolve result --value-var direct --file-var file --precedence nonempty
  [[ ! ${result+x} ]]
  result=stale
  unset direct
  ext::secret::resolve result --value-var direct --file-var file
  [[ ! ${result+x} ]]
}

@test "resolver rejects selected empty paths, invalid policies and file-output aliases" {
  local direct file='' result=old
  if ext::secret::resolve result --value-var direct --file-var file --allow-empty; then return 1; fi
  [[ $result == old ]]
  run ext::secret::resolve file --value-var direct --file-var file
  assert_failure 2
  run ext::secret::resolve result --value-var direct --file-var file --precedence nope
  assert_failure 2
  run ext::secret::resolve result --value-var direct --file-var file --mode text --mode text
  assert_failure 2
  [[ $file == '' ]]
}

@test "secret APIs work with strict options and leave caller options and traps unchanged" {
  run bash -c '
		set -euo pipefail
		source "$1/lib/lib.sh"
		lib::load_extensions secret
		trap ":" USR1
		before=$(set +o); traps=$(trap -p)
		work() {
			local value file=$2 direct
			ext::secret::read_file value "$2"
			ext::secret::resolve value --value-var direct --file-var file
			if ext::secret::read_file value "$2.missing"; then return 1; fi
			printf "survived\n"
		}
		work "$1" "$2"
		[[ $(set +o) == "$before" && $(trap -p) == "$traps" ]]
	' bash "$REPO_ROOT" "$SECRET_FILE"
  assert_success
  assert_output --partial survived
}

@test "secret generation uses exact alphabets lengths and no stdout" {
  local generated='' alphabet
  for alphabet in alphanumeric numeric ascii ASCII; do
    ext::secret::generate generated -t "$alphabet" -l 128
    [[ ${#generated} == 128 ]]
    case $alphabet in
      alphanumeric) [[ $generated != *[!a-zA-Z0-9]* ]] ;;
      numeric) [[ $generated != *[!0-9]* ]] ;;
      *) [[ $generated != *[!\ -\~]* ]] ;;
    esac
  done
  run ext::secret::generate generated
  assert_success
  assert_output ''
}

@test "secret rejection sampling discards biased bytes and preserves spaces" {
  # shellcheck disable=SC2329 # deterministic entropy fixture
  od() { printf '255 250 249 0 1 2\n'; }
  local generated=before
  ext::secret::generate generated --type numeric --length 3
  assert_equal "$generated" 901
  # shellcheck disable=SC2329
  od() { printf '190 189 0\n'; }
  ext::secret::generate generated --type ascii --length 2
  assert_equal "$generated" '~ '
}

@test "secret failures leave caller values untouched and terminate bad sources" {
  local generated=before
  # shellcheck disable=SC2329 # failed entropy source
  od() {
    printf '1 2\n'
    return 1
  }
  ext::secret::generate generated && return 1
  assert_equal "$generated" before
  # shellcheck disable=SC2329
  od() { printf '255\n'; }
  ext::secret::generate generated -t numeric -l 1 && return 1
  assert_equal "$generated" before
  # shellcheck disable=SC2329
  od() { printf ' \n'; }
  ext::secret::generate generated && return 1
  assert_equal "$generated" before
  run ext::secret::generate generated --length 0
  assert_failure 2
  run ext::secret::generate generated --type invalid
  assert_failure 2
  run ext::secret::generate PATH
  assert_failure 2
}

@test "secret generation preserves strict caller state and nonstandard IFS" {
  run bash -c '
    source "$1/lib/lib.sh"
    lib::load_extensions secret
    set -euo pipefail
    IFS=:
    result=before
    before=$(set +o; declare -p IFS; umask)
    ext::secret::generate result --type numeric --length 32
    [[ ${#result} == 32 && $result != *[!0-9]* ]]
    after=$(set +o; declare -p IFS; umask)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT"
  assert_success
  assert_output ''
}
