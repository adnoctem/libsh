#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  source "$REPO_ROOT/lib/lib.sh"
  TEST_TMP=$BATS_TEST_TMPDIR/tree
  mkdir "$TEST_TMP"
}

@test "relativize normalizes lexical nonexistent paths and root boundaries" {
  run lib::fs::relativize /a/b/../c/./file /a//b/
  assert_success
  assert_output ../c/file
  run lib::fs::relativize /../../a /b
  assert_output ../a
  run lib::fs::relativize / /a/b
  assert_output ../..
  run lib::fs::relativize /a/b /
  assert_output a/b
  run lib::fs::relativize / /
  assert_output .
  run lib::fs::relativize /a/b /a/b
  assert_output .
  run lib::fs::relativize /a/b /a/bc
  assert_output ../b
}

@test "relativize uses logical PWD and preserves newline and glob characters" {
  cd "$TEST_TMP" || return 1
  mkdir actual
  ln -s actual alias
  run lib::fs::relativize 'alias/../missing' .
  assert_output missing
  local captured
  captured=$(
    lib::fs::relativize $'../[x]/a\n\n' "$TEST_TMP"
    printf .
  )
  assert_equal "$captured" $'../[x]/a\n\n\n.'
  run lib::fs::relativize '' .
  assert_failure 2
  run lib::fs::relativize /
  assert_failure 2
}

@test "filesystem predicates distinguish types and follow explicit symlinks" {
  mkdir "$TEST_TMP/dir"
  : >"$TEST_TMP/file"
  ln -s file "$TEST_TMP/link"
  ln -s absent "$TEST_TMP/broken"
  mkfifo "$TEST_TMP/fifo"
  lib::fs::dir_exists "$TEST_TMP/dir"
  lib::fs::file_exists "$TEST_TMP/link"
  lib::fs::file_empty "$TEST_TMP/file"
  lib::fs::file_writable "$TEST_TMP/link"
  lib::fs::dir_writable "$TEST_TMP/dir"
  chmod +x "$TEST_TMP/file"
  lib::fs::file_executable "$TEST_TMP/file"
  local function_name
  for function_name in file_exists file_empty file_writable file_executable; do
    run "lib::fs::$function_name" "$TEST_TMP/dir"
    assert_failure 1
    run "lib::fs::$function_name" "$TEST_TMP/fifo"
    assert_failure 1
    run "lib::fs::$function_name" "$TEST_TMP/broken"
    assert_failure 1
    run "lib::fs::$function_name" ''
    assert_failure 2
    run "lib::fs::$function_name"
    assert_failure 2
  done
  printf data >"$TEST_TMP/file"
  run lib::fs::file_empty "$TEST_TMP/file"
  assert_failure 1
}

@test "directory emptiness includes dotfiles and dangling links despite caller glob options" {
  lib::fs::dir_empty "$TEST_TMP"
  (
    set -f
    shopt -s failglob
    GLOBIGNORE='*'
    : >"$TEST_TMP/.hidden"
    if lib::fs::dir_empty "$TEST_TMP"; then return 1; fi
    [[ $GLOBIGNORE == '*' && $- == *f* ]]
    shopt -q failglob
  )
  mkdir "$TEST_TMP/other"
  ln -s missing "$TEST_TMP/other/.broken"
  run lib::fs::dir_empty "$TEST_TMP/other"
  assert_failure 1
  run lib::fs::dir_empty "$TEST_TMP/missing"
  assert_failure 1
}

@test "filesystem access predicates and directory emptiness report denied access" {
  if [[ $EUID == 0 ]]; then skip 'effective root access bypasses ordinary permissions'; fi
  mkdir "$TEST_TMP/denied"
  : >"$TEST_TMP/file"
  chmod 000 "$TEST_TMP/denied" "$TEST_TMP/file"
  local result=0
  if lib::fs::dir_empty "$TEST_TMP/denied"; then result=1; else [[ $? == 2 ]] || result=1; fi
  if lib::fs::dir_writable "$TEST_TMP/denied"; then result=1; fi
  if lib::fs::file_writable "$TEST_TMP/file"; then result=1; fi
  chmod 700 "$TEST_TMP/denied" "$TEST_TMP/file"
  [[ $result == 0 ]]
}

@test "file_size reports exact logical bytes including sparse holes and follows explicit links" {
  printf abc >"$TEST_TMP/three"
  ln -s three "$TEST_TMP/link"
  run lib::fs::file_size "$TEST_TMP/link"
  assert_success
  assert_output 3
  dd if=/dev/null of="$TEST_TMP/sparse" bs=1 seek=1048576 2>/dev/null
  run lib::fs::file_size "$TEST_TMP/sparse"
  assert_success
  assert_output 1048576
  run lib::fs::file_size "$TEST_TMP"
  assert_failure 1
  run lib::fs::file_size ''
  assert_failure 2
}

@test "owner_get exposes numeric ownership and rejects unsupported selectors" {
  : >"$TEST_TMP/file"
  run lib::fs::owner_get "$TEST_TMP/file"
  assert_success
  assert_output "$(id -u)"
  run lib::fs::owner_get "$TEST_TMP/file" gid
  assert_output "$(id -g)"
  run lib::fs::owner_get "$TEST_TMP/file" unknown
  assert_failure 2
  run lib::fs::owner_get "$TEST_TMP/missing"
  assert_failure 1
}

@test "stat failures and malformed size output produce no partial value" {
  : >"$TEST_TMP/file"
  # shellcheck disable=SC2329 # called indirectly by the filesystem helpers
  stat() {
    printf '12\n'
    return 7
  }
  local value
  if value=$(lib::fs::file_size "$TEST_TMP/file" 2>/dev/null); then return 1; fi
  assert_equal "$value" ''
  # shellcheck disable=SC2329
  stat() { printf '9223372036854775808\n'; }
  run lib::fs::file_size "$TEST_TMP/file"
  assert_failure 1
}

@test "macOS stat selects BSD size and owner formats and protects leading hyphens" {
  cd "$TEST_TMP" || return 1
  : >-file
  # shellcheck disable=SC2329 # platform/backend fixtures
  uname() { printf 'Darwin\n'; }
  # shellcheck disable=SC2329
  stat() {
    [[ $# == 4 && $1 == -L && $2 == -f && $4 == ./-file ]] || return 8
    case $3 in %z) printf '3\n' ;; %u) printf '123\n' ;; %Sg) printf 'staff\n' ;; *) return 9 ;; esac
  }
  run lib::fs::file_size -file
  assert_success
  assert_output 3
  run lib::fs::owner_get -file
  assert_output 123
  run lib::fs::owner_get -file group
  assert_output staff
}

@test "filesystem creation helpers distinguish parents from directories and preserve files" {
  lib::fs::ensure_existence "$TEST_TMP/deep/nested/file"
  [[ -d $TEST_TMP/deep/nested && ! -e $TEST_TMP/deep/nested/file ]]
  printf keep >"$TEST_TMP/deep/nested/file"
  lib::fs::ensure_existence "$TEST_TMP/deep/nested/file"
  assert_equal "$(cat "$TEST_TMP/deep/nested/file")" keep
  lib::fs::ensure_directory "$TEST_TMP/another/dir"
  lib::fs::ensure_directory "$TEST_TMP/another/dir"
  [[ -d $TEST_TMP/another/dir ]]
  run lib::fs::ensure_directory "$TEST_TMP/deep/nested/file/child"
  assert_failure 1
  run lib::fs::ensure_existence ''
  assert_failure 2
  cd "$TEST_TMP" || return 1
  lib::fs::ensure_existence $'-dir\n/file'
  [[ -d $'-dir\n' ]]
}

@test "directory size includes hidden sparse and hard-linked files and skips child symlinks" {
  mkdir "$TEST_TMP/sub" "$TEST_TMP/empty"
  printf abc >"$TEST_TMP/.hidden"
  ln "$TEST_TMP/.hidden" "$TEST_TMP/sub/hardlink"
  printf 12345 >"$TEST_TMP/sub/five"$'\n'
  dd if=/dev/null of="$TEST_TMP/sub/sparse" bs=1 seek=1048576 2>/dev/null
  ln -s sub "$TEST_TMP/link"
  ln -s .. "$TEST_TMP/sub/loop"
  ln -s missing "$TEST_TMP/broken"
  mkfifo "$TEST_TMP/fifo"
  run lib::fs::dir_size "$TEST_TMP"
  assert_success
  assert_output 1048587
  run lib::fs::dir_size "$TEST_TMP/empty"
  assert_success
  assert_output 0
  run lib::fs::dir_size "$TEST_TMP/link"
  assert_success
  assert_output 1048584
  run lib::fs::dir_size "$TEST_TMP/.hidden"
  assert_failure 1
  run lib::fs::dir_size ''
  assert_failure 2
}

@test "directory size fails without a partial value for unreadable subtrees" {
  if [[ $EUID == 0 ]]; then skip 'effective root access bypasses ordinary permissions'; fi
  printf data >"$TEST_TMP/file"
  mkdir "$TEST_TMP/denied"
  chmod 000 "$TEST_TMP/denied"
  local value status
  if value=$(lib::fs::dir_size "$TEST_TMP" 2>/dev/null); then status=0; else status=$?; fi
  chmod 700 "$TEST_TMP/denied"
  assert_equal "$status" 1
  assert_equal "$value" ''
}

@test "directory size rejects accumulation overflow without publishing a partial sum" {
  : >"$TEST_TMP/one"
  : >"$TEST_TMP/two"
  # shellcheck disable=SC2329 # synthetic filesystem size backend
  stat() { printf '9223372036854775807\n'; }
  local value status
  if value=$(lib::fs::dir_size "$TEST_TMP" 2>/dev/null); then status=0; else status=$?; fi
  assert_equal "$status" 1
  assert_equal "$value" ''
}

@test "ownership lookup rejects dangling links consistently on both stat backends" {
  ln -s absent "$TEST_TMP/broken"
  # shellcheck disable=SC2329 # Darwin stat -L can fall back to lstat
  uname() { printf 'Darwin\n'; }
  # shellcheck disable=SC2329 # should never be called for a missing target
  stat() { printf '123\n'; }
  run lib::fs::owner_get "$TEST_TMP/broken"
  assert_failure 1
  assert_output --partial 'existing target'
}
