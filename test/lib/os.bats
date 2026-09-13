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
#######################################
# Install a uname fixture reporting Darwin on any host platform.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   None
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
fake_uname_darwin() {
  cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Darwin"
	FAKE
  chmod +x "$TEST_TMP/bin/uname"
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

  assert_output "sudo called with: -- apt-get update"
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

  assert_output "[--]
[cp]
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

@test "boot time reads btime and rejects missing duplicate or overflowing values" {
  # shellcheck disable=SC2329 # inspection fixture
  cat() { printf '%s\n' "$BOOT_FIXTURE"; }
  BOOT_FIXTURE=$'cpu 1 2 3\nbtime 1700000000\nprocesses 5'
  run lib::os::boot_time
  assert_success
  assert_output 1700000000
  local fixture
  for fixture in 'cpu 1 2' 'btime -1' 'btime 9223372036854775808' $'btime 1\nbtime 2'; do
    BOOT_FIXTURE=$fixture
    run lib::os::boot_time
    assert_failure 1
    assert_output ''
  done
}

@test "machine ID validates existing values and falls back only on read failure" {
  # shellcheck disable=SC2329 # inspection fixture
  cat() {
    [[ $1 != /etc/machine-id ]] || return 1
    printf '%s\n' "$ID_FIXTURE"
  }
  ID_FIXTURE=0123456789abcdef0123456789abcdef
  run lib::os::machine_id
  assert_success
  assert_output "$ID_FIXTURE"
  ID_FIXTURE=00000000000000000000000000000000
  run lib::os::machine_id
  assert_failure 1
  ID_FIXTURE=uninitialized
  run lib::os::machine_id
  assert_failure 1
}

@test "memory counters return exact bytes and do not estimate missing available memory" {
  # shellcheck disable=SC2329 # inspection fixture
  cat() { printf '%s\n' "$MEMORY_FIXTURE"; }
  MEMORY_FIXTURE=$'MemTotal: 12345 kB\nMemFree: 10 kB\nSwapFree: 0 kB'
  run lib::os::memory
  assert_success
  assert_output 12641280
  run lib::os::memory free
  assert_output 10240
  run lib::os::memory swap-free
  assert_output 0
  run lib::os::memory available
  assert_failure 1
  assert_output ''
  MEMORY_FIXTURE='MemTotal: 9223372036854775807 kB'
  run lib::os::memory
  assert_failure 1
  MEMORY_FIXTURE='MemTotal: 2 MB'
  run lib::os::memory
  assert_failure 1
  run lib::os::memory unknown
  assert_failure 2
}

@test "root disk lookup returns mounted logical devices and rejects virtual roots" {
  # shellcheck disable=SC2329 # findmnt fixture
  findmnt() {
    [[ $* == '-n -r -o SOURCE --target /' ]] || return 1
    printf '%s\n' "$DISK_FIXTURE"
  }
  DISK_FIXTURE='/dev/mapper/root[/@root]'
  run lib::os::disk_device_id
  assert_success
  assert_output /dev/mapper/root
  DISK_FIXTURE=/dev/nvme0n1p2
  run lib::os::disk_device_id
  assert_output /dev/nvme0n1p2
  DISK_FIXTURE=overlay
  run lib::os::disk_device_id
  assert_failure 1
  DISK_FIXTURE=$'/dev/sda\n/dev/sdb'
  run lib::os::disk_device_id
  assert_failure 1
}

@test "disk capacity parses only one fdisk byte header under locale C" {
  # shellcheck disable=SC2329 # fdisk fixture
  fdisk() {
    [[ $LC_ALL == C && $* == '-l -- /dev/test' ]] || return 1
    printf '%s\n' "$CAPACITY_FIXTURE"
  }
  CAPACITY_FIXTURE=$'Disk /dev/test: 1 TiB, 1099511627776 bytes, 2147483648 sectors\nDisklabel type: gpt'
  run lib::os::disk_capacity /dev/test
  assert_success
  assert_output 1099511627776
  CAPACITY_FIXTURE='Disk /dev/test: invalid'
  run lib::os::disk_capacity /dev/test
  assert_failure 1
  CAPACITY_FIXTURE=$'Disk /dev/test: 1 KiB, 1024 bytes, 2 sectors\nDisk /dev/other: 1 KiB, 1024 bytes, 2 sectors'
  run lib::os::disk_capacity /dev/test
  assert_failure 1
  run lib::os::disk_capacity
  assert_failure 2
  run lib::os::disk_capacity --help
  assert_failure 2
}

@test "Linux inspection explicitly fails on unsupported platforms" {
  fake_uname_darwin
  local fn
  for fn in boot_time machine_id memory disk_device_id; do
    run "lib::os::$fn"
    assert_failure 1
  done
  run lib::os::disk_capacity /dev/test
  assert_failure 1
  run lib::os::metadata --id
  assert_failure 1
}

@test "metadata uses allowlisted fields branch fallback and last duplicate values" {
  # shellcheck disable=SC2329 # os-release fixture
  cat() { printf '%s\n' "$RELEASE_FIXTURE"; }
  RELEASE_FIXTURE=$'ID=first\nID=example\nVERSION_ID="24.04.2"\nNAME="Example Linux"\nVERSION_CODENAME=stable'
  run lib::os::metadata --id
  assert_output example
  run lib::os::metadata --name
  assert_output 'Example Linux'
  run lib::os::metadata --branch
  assert_output 24
  RELEASE_FIXTURE+=$'\nBRANCH="rolling"'
  run lib::os::metadata --branch
  assert_output rolling
  run lib::os::metadata --pretty-name
  assert_failure 1
  run lib::os::metadata --arbitrary
  assert_failure 2
}

@test "metadata handles shell quoting as data and never evaluates commands" {
  # shellcheck disable=SC2329 # os-release fixture
  cat() { printf '%s\n' "$QUOTING_FIXTURE"; }
  QUOTING_FIXTURE="NAME=\"\$(touch '$TEST_TMP/executed')\""
  run lib::os::metadata --name
  assert_success
  assert_output "\$(touch '$TEST_TMP/executed')"
  [[ ! -e $TEST_TMP/executed ]]

  QUOTING_FIXTURE='NAME="A \"quoted\" name with \\ backslash"'
  run lib::os::metadata --name
  assert_output 'A "quoted" name with \ backslash'
  QUOTING_FIXTURE="NAME='single quoted'"
  run lib::os::metadata --name
  assert_output 'single quoted'
  QUOTING_FIXTURE='NAME="unclosed'
  run lib::os::metadata --name
  assert_failure 1
}

@test "account existence distinguishes absent records and backend errors" {
  # shellcheck disable=SC2329 # NSS fixture
  getent() {
    case "$1:$2" in
      passwd:example) printf 'example:x:123:456::/home/example:/bin/sh\n' ;;
      group:example) printf 'example:x:456:\n' ;;
      *:absent) return 2 ;;
      *) return 1 ;;
    esac
  }
  run lib::os::user_exists example
  assert_success
  assert_output ''
  run lib::os::group_exists example
  assert_success
  run lib::os::user_exists absent
  assert_failure 1
  run lib::os::group_exists backend
  assert_failure 3
  run lib::os::user_exists --help
  assert_failure 2
}

@test "ensure functions leave existing accounts untouched despite differing options" {
  # shellcheck disable=SC2329 # NSS fixture
  getent() {
    if [[ $1 == passwd ]]; then
      printf 'example:x:123:456::/home/example:/bin/sh\n'
    else
      printf 'example:x:456:\n'
    fi
  }
  # shellcheck disable=SC2329 # mutation must never occur
  useradd() {
    touch "$TEST_TMP/unexpected"
    return 99
  }
  # shellcheck disable=SC2329
  groupadd() {
    touch "$TEST_TMP/unexpected"
    return 99
  }
  run lib::os::user_ensure example --id 999 --home /different --system
  assert_success
  assert_output "user 'example' already exists."
  run lib::os::group_ensure example --id 999 --system
  assert_success
  [[ ! -e $TEST_TMP/unexpected ]]
}

@test "account creation forwards frontend options and system policy" {
  # shellcheck disable=SC2329 # NSS fixture
  getent() { return 2; }
  # shellcheck disable=SC2329 # mutation fixture
  useradd() { printf '<%s>' "$@" >"$TEST_TMP/arguments"; }
  # shellcheck disable=SC2329
  groupadd() { printf '<%s>' "$@" >"$TEST_TMP/arguments"; }
  run lib::os::user_ensure example -i 00123 -g staff -a audio,00456 -h '/srv/a home' -s
  assert_success
  assert_equal "$(cat "$TEST_TMP/arguments")" '<--uid><123><--system><--gid><staff><--home-dir></srv/a home><--groups><audio,456><--><example>'
  run lib::os::group_ensure example -i 00456 -s
  assert_success
  assert_equal "$(cat "$TEST_TMP/arguments")" '<--gid><456><--system><--><example>'
}

@test "update functions require existing accounts and append supplementary groups" {
  # shellcheck disable=SC2329 # NSS fixture
  getent() {
    [[ $2 != absent ]] || return 2
    if [[ $1 == passwd ]]; then
      printf 'example:x:123:456::/home/example:/bin/sh\n'
    else
      printf 'example:x:456:\n'
    fi
  }
  # shellcheck disable=SC2329 # mutation fixture
  usermod() { printf '<%s>' "$@" >"$TEST_TMP/arguments"; }
  # shellcheck disable=SC2329
  groupmod() { printf '<%s>' "$@" >"$TEST_TMP/arguments"; }
  run lib::os::user_update example -i 124 -g staff -a audio -h /srv/new
  assert_success
  assert_equal "$(cat "$TEST_TMP/arguments")" '<--uid><124><--gid><staff><--home></srv/new><--append><--groups><audio><--><example>'
  run lib::os::group_update example -i 457
  assert_success
  assert_equal "$(cat "$TEST_TMP/arguments")" '<--gid><457><--><example>'
  run lib::os::user_update absent -i 9
  assert_failure 1
  run lib::os::user_update example --system
  assert_failure 2
  run lib::os::group_update example
  assert_failure 2
}

@test "account backend errors and invalid options cannot trigger a mutation" {
  # shellcheck disable=SC2329 # NSS fixture
  getent() { return 1; }
  # shellcheck disable=SC2329 # mutation sentinel
  useradd() { touch "$TEST_TMP/unexpected"; }
  run lib::os::user_ensure example
  assert_failure 1
  [[ ! -e $TEST_TMP/unexpected ]]

  # shellcheck disable=SC2329
  getent() { return 2; }
  run lib::os::user_ensure example --id 4294967295
  assert_failure 2
  run lib::os::user_ensure example --append-groups 'one,,two'
  assert_failure 2
  run lib::os::user_ensure example --home relative
  assert_failure 2
  [[ ! -e $TEST_TMP/unexpected ]]

  # shellcheck disable=SC2329
  useradd() { return 9; }
  run lib::os::user_ensure example
  assert_failure 1
}

@test "account wrappers preserve strict caller state and local parser arrays" {
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    getent() { return 2; }
    groupadd() { :; }
    declare -a OPTS=(caller)
    declare -A OPTS_HELP=([caller]=help) OPTS_VALUES=([caller]=value)
    before=$(set +o; declare -p OPTS OPTS_HELP OPTS_VALUES; pwd; umask)
    lib::os::group_ensure example
    getent() { printf "example:x:123:\n"; }
    status=0
    lib::os::group_update example || status=$?
    [[ $status == 2 ]]
    after=$(set +o; declare -p OPTS OPTS_HELP OPTS_VALUES; pwd; umask)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT"
  assert_success
  assert_output ''
}

@test "recursive configure includes hidden files and applies directory modes after traversal" {
  mkdir -p "$TEST_TMP/tree/sub"
  touch "$TEST_TMP/tree/.hidden" "$TEST_TMP/tree/sub/child"
  chmod 2755 "$TEST_TMP/tree/sub"
  run lib::os::recursive_configure "$TEST_TMP/tree" -f 640 -d 700
  assert_success
  assert_output ''
  local mode
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/tree/sub" attributes)
  [[ ${mode%% *} == *700 ]]
  [[ ${mode%% *} != *2700 ]]
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/tree/.hidden" attributes)
  [[ ${mode%% *} == *640 ]]
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/tree/sub/child" attributes)
  [[ ${mode%% *} == *640 ]]
}

@test "recursive configure follows links by default and no-dereference skips their targets" {
  mkdir -p "$TEST_TMP/tree" "$TEST_TMP/outside"
  touch "$TEST_TMP/outside/file"
  chmod 600 "$TEST_TMP/outside/file"
  ln -s ../outside "$TEST_TMP/tree/link"
  lib::os::recursive_configure "$TEST_TMP/tree" -f 644 -n
  local mode
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/outside/file" attributes)
  [[ ${mode%% *} == *600 ]]
  lib::os::recursive_configure "$TEST_TMP/tree" -f 644
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/outside/file" attributes)
  [[ ${mode%% *} == *644 ]]

  lib::os::recursive_configure "$TEST_TMP/tree/link/" -f 600 -n
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/outside/file" attributes)
  [[ ${mode%% *} == *644 ]]
}

@test "recursive ownership uses chown -h for links without changing their modes" {
  mkdir "$TEST_TMP/tree"
  ln -s absent "$TEST_TMP/tree/broken"
  # shellcheck disable=SC2329 # ownership fixture
  chown() { printf '<%s>' "$@" >>"$TEST_TMP/chown"; }
  run lib::os::recursive_configure "$TEST_TMP/tree" -u 123 -g 456 -f 600 -n
  assert_success
  [[ $(cat "$TEST_TMP/chown") == *"<-h><--><123:456><$TEST_TMP/tree/broken>"* ]]
  [[ -L $TEST_TMP/tree/broken ]]
}

@test "recursive configure rejects loops before mutations and validates modes first" {
  mkdir -p "$TEST_TMP/tree/sub"
  touch "$TEST_TMP/tree/file"
  ln -s .. "$TEST_TMP/tree/sub/loop"
  # shellcheck disable=SC2329 # mutation sentinel
  chmod() { touch "$TEST_TMP/unexpected"; }
  run lib::os::recursive_configure "$TEST_TMP/tree" -f 600
  assert_failure 1
  [[ ! -e $TEST_TMP/unexpected ]]
  run lib::os::recursive_configure "$TEST_TMP/tree" -f 888
  assert_failure 2
  run lib::os::recursive_configure "$TEST_TMP/tree" -u 'user:group'
  assert_failure 2
  run lib::os::recursive_configure "$TEST_TMP/tree" -n
  assert_failure 2
  [[ ! -e $TEST_TMP/unexpected ]]
}

@test "recursive configure rejects cycles even when find reports success" {
  mkdir -p "$TEST_TMP/tree/sub"
  touch "$TEST_TMP/tree/file"
  ln -s .. "$TEST_TMP/tree/sub/loop"
  # shellcheck disable=SC2329 # macOS find includes the cycle without failing
  find() {
    printf '%s\0' "$TEST_TMP/tree/file" "$TEST_TMP/tree/sub/loop" \
      "$TEST_TMP/tree/sub" "$TEST_TMP/tree"
  }
  # shellcheck disable=SC2329 # mutation sentinels
  chmod() { touch "$TEST_TMP/unexpected"; }
  # shellcheck disable=SC2329
  chown() { touch "$TEST_TMP/unexpected"; }

  run lib::os::recursive_configure "$TEST_TMP/tree" -u 123 -f 600
  assert_failure 1
  [[ ! -e $TEST_TMP/unexpected ]]
}

@test "recursive configure permits aliases without cycles" {
  mkdir -p "$TEST_TMP/tree/sub"
  touch "$TEST_TMP/tree/sub/file"
  ln -s sub "$TEST_TMP/tree/alias"
  ln -s sub "$TEST_TMP/tree/second"

  run lib::os::recursive_configure "$TEST_TMP/tree" -f 600
  assert_success
  local mode
  mode=$(__libsh_fs_stat "$TEST_TMP/tree/sub/file" attributes)
  [[ ${mode%% *} == *600 ]]
}

@test "recursive configure preserves newline paths and strict caller state" {
  mkdir -p "$TEST_TMP/tree"
  touch "$TEST_TMP/tree/"$'a\nb'
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    trap ": caller" EXIT
    umask 027
    before=$(set +o; trap -p; pwd; umask)
    lib::os::recursive_configure "$2/tree" -f 600
    after=$(set +o; trap -p; pwd; umask)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT" "$TEST_TMP"
  assert_success
  local mode
  mode=$(PATH="$ORIGINAL_PATH" __libsh_fs_stat "$TEST_TMP/tree/"$'a\nb' attributes)
  [[ ${mode%% *} == *600 ]]
}

@test "root_exec maps preservation aliases to sudo -E before the command boundary" {
  if [[ $EUID == 0 ]]; then skip 'sudo branch requires nonroot'; fi

  # shellcheck disable=SC2329 # called indirectly by root_exec
  sudo() { printf '<%s>\n' "$@"; }

  local option
  for option in -e --preserve-environment; do
    run lib::os::root_exec "$option" -- command 'a b' '' --preserve-environment -e
    assert_success
    assert_output $'<-E>\n<-->\n<command>\n<a b>\n<>\n<--preserve-environment>\n<-e>'
  done

  run lib::os::root_exec -- command -e
  assert_success
  assert_output $'<-->\n<command>\n<-e>'

  run lib::os::root_exec -e --preserve-environment command
  assert_success
  assert_output $'<-E>\n<-->\n<command>'
}

@test "root_exec rejects invalid wrapper invocations before execution" {
  # shellcheck disable=SC2329 # called indirectly by root_exec
  sudo() { printf 'must not execute\n'; }

  run lib::os::root_exec
  assert_failure 2
  run lib::os::root_exec -e
  assert_failure 2
  run lib::os::root_exec --
  assert_failure 2
  run lib::os::root_exec --preserve-environment ''
  assert_failure 2
  run lib::os::root_exec --unknown command
  assert_failure 2
  refute_output --partial 'must not execute'
}

# shellcheck disable=SC2016 # literal data and source code for the child Bash
@test "root_exec preservation retains exported values streams and failure status" {
  # Stand-in executes only the caller's harmless Bash command, never real sudo.
  # shellcheck disable=SC2329 # called indirectly by root_exec
  sudo() {
    [[ $1 == -E && $2 == -- ]] || return 98
    shift 2
    "$@"
  }

  export LIBSH_ROOT_EXEC_TEST_VALUE='spaces and literal $text'
  local stdout="$TEST_TMP/stdout" stderr="$TEST_TMP/stderr" status=0
  lib::os::root_exec -e bash -c \
    'printf "%s" "$LIBSH_ROOT_EXEC_TEST_VALUE"; printf error >&2; exit 7' \
    >"$stdout" 2>"$stderr" || status=$?

  assert_equal "$status" 7
  assert_equal "$(cat "$stdout")" 'spaces and literal $text'
  assert_equal "$(cat "$stderr")" error
}

@test "root_exec consumes preservation options without sudo when already root" {
  if [[ $EUID != 0 ]]; then skip 'direct branch requires root'; fi
  # shellcheck disable=SC2329 # called indirectly by root_exec
  sudo() { return 98; }

  local option
  for option in -e --preserve-environment; do
    run lib::os::root_exec "$option" -- printf '<%s>\n' 'a b' '' -e
    assert_success
    assert_output $'<a b>\n<>\n<-e>'
  done
}

@test "root_exec preserves strict caller state and propagates sudo rejection" {
  run bash -c '
    set -euo pipefail
    source "$1/lib/lib.sh"
    sudo() { return 9; }
    declare -a OPTS=(sentinel)
    declare -A OPTS_HELP=([sentinel]=description) OPTS_VALUES=([sentinel]=value)
    trap ":" USR1
    before=$(set +o); traps=$(trap -p); mask=$(umask); directory=$PWD
    status=0
    lib::os::root_exec -e false || status=$?
    if [[ $EUID == 0 ]]; then [[ $status == 1 ]]; else [[ $status == 9 ]]; fi
    [[ $(set +o) == "$before" && $(trap -p) == "$traps" ]]
    [[ $(umask) == "$mask" && $PWD == "$directory" ]]
    [[ ${OPTS[0]} == sentinel && ${OPTS_HELP[sentinel]} == description && ${OPTS_VALUES[sentinel]} == value ]]
  ' _ "$REPO_ROOT"
  assert_success
}
