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

@test "file replacement expands ERE captures and sed replacement syntax on every line" {
  printf 'one=12 one=34\ntwo=56\n' >"$TEST_TMP/file"
  # shellcheck disable=SC1003  # The final two backslashes are sed replacement data.
  run lib::fs::file_replace_content "$TEST_TMP/file" '(one|two)=([0-9]+)' '\2:\1:[&]:\&:\\'
  assert_success
  assert_output ''
  printf '12:one:[one=12]:&:\\ 34:one:[one=34]:&:\\\n56:two:[two=56]:&:\\\n' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
}

@test "file replacement preserves terminal newlines CRLF and literal replacement newlines" {
  local original
  for original in 'word' $'word\n' $'word\n\n' $'word\r\n'; do
    printf '%s' "$original" >"$TEST_TMP/file"
    lib::fs::file_replace_content "$TEST_TMP/file" word $'new\nline\n'
    printf '%s' "${original/word/$'new\nline\n'}" >"$TEST_TMP/expected"
    cmp "$TEST_TMP/file" "$TEST_TMP/expected"
  done
}

@test "multiline replacement matches file boundaries and embedded newlines" {
  printf 'begin\nfirst\nlast\nend\n' >"$TEST_TMP/file"
  lib::fs::file_replace_content_multiline "$TEST_TMP/file" $'^begin\n(first.*last)\nend\n$' $'<\\1>\n'
  printf '<first\nlast>\n' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  printf 'begin\nend' >"$TEST_TMP/file"
  lib::fs::file_replace_content_multiline "$TEST_TMP/file" 'begin\nend$' 'done'
  printf '%s' 'done' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  : >"$TEST_TMP/file"
  lib::fs::file_replace_content_multiline "$TEST_TMP/file" '^$' text
  printf text >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
}

@test "line replacement cannot match across lines and no match leaves identity unchanged" {
  printf 'first\nlast\n' >"$TEST_TMP/file"
  cp -p "$TEST_TMP/file" "$TEST_TMP/expected"
  local before
  before=$(__libsh_fs_edit_identity "$TEST_TMP/file")
  run lib::fs::file_replace_content "$TEST_TMP/file" 'first.*last' changed
  assert_failure 1
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
  assert_equal "$(__libsh_fs_edit_identity "$TEST_TMP/file")" "$before"

  run lib::fs::file_replace_content "$TEST_TMP/file" first first
  assert_success
  assert_equal "$(__libsh_fs_edit_identity "$TEST_TMP/file")" "$before"
}

@test "line removal preserves surviving terminators and can remove all lines" {
  printf 'drop\nkeep\ndrop' >"$TEST_TMP/file"
  lib::fs::file_remove_content "$TEST_TMP/file" '^drop$'
  printf 'keep\n' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  printf 'drop\nkeep' >"$TEST_TMP/file"
  lib::fs::file_remove_content "$TEST_TMP/file" drop
  printf keep >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  lib::fs::file_remove_content "$TEST_TMP/file" keep
  [[ ! -s $TEST_TMP/file ]]
  run lib::fs::file_remove_content "$TEST_TMP/file" '.*'
  assert_failure 1
}

@test "insertion uses the last matching line and literal text with necessary separators" {
  printf 'mark\nkeep\nmark\nsuffix' >"$TEST_TMP/file"
  lib::fs::file_append_content_after_last_match "$TEST_TMP/file" mark 'literal & \1'
  printf 'mark\nkeep\nmark\nliteral & \\1\nsuffix' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  printf mark >"$TEST_TMP/file"
  lib::fs::file_append_content_after_last_match "$TEST_TMP/file" mark $'one\ntwo\n'
  printf 'mark\none\ntwo\n' >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  lib::fs::file_append_content_after_last_match "$TEST_TMP/file" two ''
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
  run lib::fs::file_append_content_after_last_match "$TEST_TMP/file" missing ''
  assert_failure 1
}

@test "editing follows relative symlink chains and no-dereference refuses them" {
  local file=$TEST_TMP/$'file\n\n' flag
  printf old >"$file"
  ln -s $'file\n\n' "$TEST_TMP/link"
  ln -s link "$TEST_TMP/chain"
  for flag in -n --no-dereference; do
    run lib::fs::file_replace_content "$TEST_TMP/chain" old new "$flag"
    assert_failure 1
    assert_equal "$(cat "$file")" old
  done

  lib::fs::file_replace_content "$TEST_TMP/chain" old new
  assert_equal "$(cat "$file")" new
  [[ -L $TEST_TMP/link && -L $TEST_TMP/chain ]]
  lib::fs::file_replace_content "$file" new newer -n
  assert_equal "$(cat "$file")" newer
}

@test "editing refuses hard links broken links loops directories and special files" {
  printf original >"$TEST_TMP/file"
  ln "$TEST_TMP/file" "$TEST_TMP/hard"
  ln -s missing "$TEST_TMP/broken"
  ln -s loop "$TEST_TMP/loop"
  mkfifo "$TEST_TMP/fifo"
  local path
  for path in file hard broken loop fifo absent .; do
    run lib::fs::file_replace_content "$TEST_TMP/$path" original changed
    assert_failure 1
  done
  assert_equal "$(cat "$TEST_TMP/file")" original
  assert_equal "$(cat "$TEST_TMP/hard")" original
}

@test "editing preserves mode and ownership including a read-only target" {
  printf old >"$TEST_TMP/file"
  chmod 440 "$TEST_TMP/file"
  local before after
  before=$(__libsh_fs_edit_identity "$TEST_TMP/file")
  lib::fs::file_replace_content "$TEST_TMP/file" old new
  after=$(__libsh_fs_edit_identity "$TEST_TMP/file")
  assert_equal "${after#* * * }" "${before#* * * }"
  assert_equal "$(cat "$TEST_TMP/file")" new
}

@test "invalid editing arguments expressions and NUL data leave the original untouched" {
  printf 'old\n' >"$TEST_TMP/file"
  cp "$TEST_TMP/file" "$TEST_TMP/expected"
  local pattern
  for pattern in '[' "old\\" ''; do
    run lib::fs::file_replace_content "$TEST_TMP/file" "$pattern" new
    assert_failure 2
    cmp "$TEST_TMP/file" "$TEST_TMP/expected"
  done
  run lib::fs::file_replace_content "$TEST_TMP/file" old '\1'
  assert_failure 2
  run lib::fs::file_replace_content "$TEST_TMP/file" old '\n'
  assert_failure 2
  run lib::fs::file_replace_content "$TEST_TMP/file" old new --unknown
  assert_failure 2
  run lib::fs::file_replace_content "$TEST_TMP/file" old
  assert_failure 2
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"

  printf 'old\0data' >"$TEST_TMP/file"
  cp "$TEST_TMP/file" "$TEST_TMP/expected"
  run lib::fs::file_replace_content "$TEST_TMP/file" old new
  assert_failure 2
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
}

@test "replacement delimiters and shell-looking text cannot inject commands" {
  printf 'old/path|name\n' >"$TEST_TMP/file"
  # shellcheck disable=SC2016  # Exercise literal shell syntax as replacement data.
  local replacement='$(touch forbidden); / | : @ % ~ , ; # ! = + _ &'
  lib::fs::file_replace_content "$TEST_TMP/file" 'old/path\|name' "$replacement"
  printf '%s\n' "${replacement%&}old/path|name" >"$TEST_TMP/expected"
  cmp "$TEST_TMP/file" "$TEST_TMP/expected"
  [[ ! -e forbidden ]]
}

@test "failed transformation and commit leave the file untouched and clean temporary files" {
  printf old >"$TEST_TMP/file"
  local command_name
  for command_name in sed mv chmod; do
    run bash -c '
      source "$1/lib/lib.sh"
      function sed() { if [[ $FAIL_COMMAND == sed ]]; then return 1; fi; command sed "$@"; }
      function mv() { if [[ $FAIL_COMMAND == mv ]]; then return 1; fi; command mv "$@"; }
      function chmod() { if [[ $FAIL_COMMAND == chmod ]]; then return 1; fi; command chmod "$@"; }
      FAIL_COMMAND=$3
      lib::fs::file_replace_content "$2/file" old new
    ' _ "$REPO_ROOT" "$TEST_TMP" "$command_name"
    assert_failure
    assert_equal "$(cat "$TEST_TMP/file")" old
    local leftovers=("$TEST_TMP"/.libsh-edit.*)
    [[ ! -e ${leftovers[0]} ]]
  done
}

@test "editing detects concurrent changes before committing staged bytes" {
  printf old >"$TEST_TMP/file"
  run bash -c '
    source "$1/lib/lib.sh"
    target=$2/file
    function sed() {
      command sed "$@" || return
      printf concurrent >"$target"
    }
    lib::fs::file_replace_content "$target" old new
  ' _ "$REPO_ROOT" "$TEST_TMP"
  assert_failure 1
  assert_equal "$(cat "$TEST_TMP/file")" concurrent
}

@test "editing preserves strict caller state and parser arrays" {
  printf old >"$TEST_TMP/file"
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    umask 027
    trap ": caller trap" EXIT
    declare -a OPTS=(caller)
    declare -A OPTS_HELP=([caller]=help) OPTS_VALUES=([caller]=value)
    before=$(set +o; trap -p; pwd; umask; declare -p OPTS OPTS_HELP OPTS_VALUES)
    lib::fs::file_replace_content "$2/file" old new
    lib::fs::file_remove_content "$2/file" missing 2>/dev/null && exit 1
    after=$(set +o; trap -p; pwd; umask; declare -p OPTS OPTS_HELP OPTS_VALUES)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT" "$TEST_TMP"
  assert_success
  assert_output ''
  assert_equal "$(cat "$TEST_TMP/file")" new
}

@test "owner_set forwards owner forms and no-dereference without recursion" {
  # shellcheck disable=SC2329 # ownership fixture
  chown() { printf '<%s>' "$@" >"$TEST_TMP/chown"; }
  run lib::fs::owner_set "$TEST_TMP/link/" 123:456 -n
  assert_success
  assert_output ''
  assert_equal "$(cat "$TEST_TMP/chown")" "<-h><--><123:456><$TEST_TMP/link>"
  lib::fs::owner_set "$TEST_TMP/file" :staff
  assert_equal "$(cat "$TEST_TMP/chown")" "<--><:staff><$TEST_TMP/file>"
  run lib::fs::owner_set "$TEST_TMP/file" --reference=other
  assert_failure 2
  run lib::fs::owner_set "$TEST_TMP/file" user:group:extra
  assert_failure 2
}

@test "owner_set propagates backend failure and accepts leading-hyphen paths safely" {
  # shellcheck disable=SC2329 # ownership fixture
  chown() {
    [[ $* == '-- 123 ./-file' ]] || return 9
    return 1
  }
  run lib::fs::owner_set -file 123
  assert_failure 1
}

@test "editing supports BSD readlink without requesting zero bytes from head" {
  readlink() {
    [[ $1 == -n ]] || return 1
    command readlink "$@"
  }
  head() {
    [[ $1 != -c || $2 != 0 ]] || return 1
    command head "$@"
  }

  local target="$TEST_TMP/"$'target\n'
  printf 'old\n' >"$target"
  ln -s "$target" "$TEST_TMP/link"
  run lib::fs::file_replace_content "$TEST_TMP/link" old new
  assert_success
  run lib::fs::file_remove_content "$TEST_TMP/link" new
  assert_success
  [[ ! -s $target ]]
}
