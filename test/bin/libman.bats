#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  export HOME="$BATS_TEST_TMPDIR/home"
  local test_root
  test_root=$(cd -P -- "$BATS_TEST_TMPDIR" && pwd)
  export LIBSH_INSTALL_DIR="$test_root/quote' dollar\$ space/libsh"
  export LIBMAN_BIN_DIR="$BATS_TEST_TMPDIR/commands"
  export FIXTURES="$BATS_TEST_TMPDIR/releases"
  unset LIBSH_EXTENSIONS LIBSH_DIR LIBSH_VERSION LIBSH_REPO INCLUDE_TOOLS LIBSH_TOOLS_DIR LIBSH_INIT_SHELL LIBSH_PROFILE_TARGETS LIBSH_NO_MODIFY_PROFILE
  mkdir -p "$HOME" "$FIXTURES" "$BATS_TEST_TMPDIR/fake"
  cat >"$BATS_TEST_TMPDIR/fake/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${@: -1}" >>"$FIXTURES/downloads"
[[ $1 == -fsSL && $2 == --connect-timeout && $4 == --max-time && $6 == -o ]]
if [[ $7 == /dev/null ]]; then
  printf 'https://github.com/%s/releases/tag/v2.0.0' "${LIBSH_REPO:-adnoctem/libsh}"
else
  url=${8%/*}
  cp "$FIXTURES/${url##*/}/${8##*/}" "$7"
fi
CURL
  chmod +x "$BATS_TEST_TMPDIR/fake/curl"
  export PATH="$BATS_TEST_TMPDIR/fake:$PATH"
  make_release 1.0.0
  make_release 2.0.0
}

#######################################
# Build a synthetic release from checkout sources for installer tests.
# Globals:
#   REPO_ROOT, FIXTURES, BATS_TEST_TMPDIR (read)
# Arguments:
#   1 - Release version
# Outputs:
#   Release archives and checksums under FIXTURES; command errors stderr.
# Returns:
#   The checksum-generation status; setup failures also fail the BATS test.
#######################################
make_release() {
  local version=$1 dir="$FIXTURES/v$1" src="$BATS_TEST_TMPDIR/source"
  mkdir -p "$dir" "$src/lib" "$src/bin" "$src/tools" "$src/extensions"
  cp "$REPO_ROOT/lib/"*.sh "$src/lib/"
  cp "$REPO_ROOT/extensions/"*.sh "$src/extensions/"
  local extension
  for extension in "$src"/extensions/lib*.sh; do
    extension=${extension##*/lib}
    extension=${extension%.sh}
    tar -czf "$dir/libsh-ext-$extension-$version.tar.gz" -C "$src" "extensions/lib$extension.sh"
  done
  cp "$REPO_ROOT/bin/libman" "$src/bin/libman"
  printf '# version %s\n' "$version" >>"$src/bin/libman"
  printf '# fixture\n' >"$src/tools/release-prepare.sh"
  tar -czf "$dir/libsh-lib-$version.tar.gz" -C "$src" lib
  tar -czf "$dir/libsh-bin-$version.tar.gz" -C "$src" bin
  tar -czf "$dir/libsh-tools-$version.tar.gz" -C "$src" tools
  (cd "$dir" && { if command -v sha256sum >/dev/null; then sha256sum ./*.tar.gz; else shasum -a 256 ./*.tar.gz; fi; } | sed 's|  ./|  |' >CHECKSUMS_SHA256.txt)
}

#######################################
# Install the baseline fixture release and require success.
# Globals:
#   REPO_ROOT (read); BATS run result variables (written)
# Arguments:
#   1+ - Additional installer arguments
# Outputs:
#   BATS assertion diagnostics on failure.
# Returns:
#   The assert_success status.
#######################################
install_release() {
  run bash "$REPO_ROOT/bin/install" --version 1.0.0 "$@"
  assert_success
}

@test "install, offline discovery, update, self-update and uninstall" {
  install_release
  [[ -L $LIBSH_INSTALL_DIR && -x $LIBMAN_BIN_DIR/libman ]]
  [[ ! -e $HOME/.bashrc && ! -e $HOME/.zshrc ]]
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  # Installed command remembers paths when invoked without installation variables.
  run env -u LIBSH_INSTALL_DIR -u LIBMAN_BIN_DIR "$LIBMAN_BIN_DIR/libman" path
  assert_success
  assert_output "$LIBSH_INSTALL_DIR"
  run "$LIBMAN_BIN_DIR/libman" update
  assert_success
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 2.0.0 ]]
  [[ -r $old/lib/lib.sh ]]
  run "$LIBMAN_BIN_DIR/libman" self-update 2.0.0
  assert_success
  run "$LIBMAN_BIN_DIR/libman" status
  assert_success
  assert_output --partial 'Manager: 2.0.0'
  run "$LIBMAN_BIN_DIR/libman" uninstall --yes
  assert_success
  [[ ! -e $LIBSH_INSTALL_DIR.libman && ! -L $LIBSH_INSTALL_DIR && ! -L $LIBMAN_BIN_DIR/libman ]]
}

@test "opt-in Bash block is quoted, idempotent and preserves rc symlinks and PATH" {
  # shellcheck disable=SC2016 # literal rc file content
  printf 'export EXISTING=yes\nexport PATH="/my/bin:$PATH"\n' >"$HOME/config"
  ln -s config "$HOME/.bashrc"
  install_release --init-shell bash
  cp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/expected"
  install_release --init-shell bash
  cmp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/expected"
  [[ -L $HOME/.bashrc && ! -e $HOME/.zshrc ]]
  run bash -c 'source "$HOME/.bashrc"; [[ $EXISTING == yes && $PATH == /my/bin:* ]]; printf "%s" "$LIBSH_DIR"'
  assert_success
  assert_output "$LIBSH_INSTALL_DIR"
  run grep -c '^export PATH=' "$HOME/.bashrc"
  assert_output 1
}

@test "Zsh setup writes only the export block; BASH_ENV remains untouched" {
  printf '# keep\n' >"$HOME/.zshrc"
  export BASH_ENV="$HOME/bash-env"
  printf '# original\n' >"$BASH_ENV"
  cp "$BASH_ENV" "$HOME/original"
  install_release --init-shell zsh
  cmp "$BASH_ENV" "$HOME/original"
  run grep -E 'PATH|source|BASH_ENV' "$HOME/.zshrc"
  assert_failure 1
  [[ ! -e $HOME/.bashrc ]]
}

@test "malformed rc blocks leave the rc file and installed release unchanged" {
  install_release
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  printf '# >>> libsh LIBSH_DIR >>>\nkeep me\n' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$HOME/original"
  run "$LIBMAN_BIN_DIR/libman" update --init-shell bash
  assert_failure
  cmp "$HOME/.bashrc" "$HOME/original"
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
}

@test "checksum failures preserve current release and release-specific files do not leak" {
  install_release
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  printf '# stale\n' >"$LIBSH_INSTALL_DIR/old-module.sh"
  printf 'broken' >>"$FIXTURES/v2.0.0/libsh-lib-2.0.0.tar.gz"
  run "$LIBMAN_BIN_DIR/libman" update
  assert_failure
  assert_output --partial 'Checksum mismatch'
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
  make_release 2.0.0
  run "$LIBMAN_BIN_DIR/libman" update
  assert_success
  [[ ! -f $LIBSH_INSTALL_DIR/old-module.sh && -f $old/lib/old-module.sh ]]
}

@test "legacy installs are preserved and tools are remembered" {
  mkdir -p "$LIBSH_INSTALL_DIR"
  printf '# legacy\n' >"$LIBSH_INSTALL_DIR/lib.sh"
  install_release --include-tools
  [[ -r $LIBSH_INSTALL_DIR.libman-backup/lib.sh ]]
  run "$LIBMAN_BIN_DIR/libman" update
  assert_success
  [[ -r ${LIBSH_INSTALL_DIR%/*}/libsh-tools/release-prepare.sh ]]
  run "$LIBMAN_BIN_DIR/libman" uninstall --yes
  assert_success
  [[ -r $LIBSH_INSTALL_DIR.libman-backup/lib.sh && ! -L ${LIBSH_INSTALL_DIR%/*}/libsh-tools ]]
}

@test "unsafe or overlapping destinations and unrelated commands are refused" {
  run bash "$REPO_ROOT/bin/libman" install 1.0.0 --install-dir "$HOME/../home"
  assert_failure
  run bash "$REPO_ROOT/bin/libman" install 1.0.0 --bin-dir "$LIBSH_INSTALL_DIR/commands"
  assert_failure
  mkdir -p "$LIBMAN_BIN_DIR"
  printf 'unrelated\n' >"$LIBMAN_BIN_DIR/libman"
  run bash "$REPO_ROOT/bin/libman" install 1.0.0
  assert_failure
  [[ $(<"$LIBMAN_BIN_DIR/libman") == unrelated ]]
}

@test "a held installation lock prevents changes" {
  install_release
  mkdir "$LIBSH_INSTALL_DIR.libman-lock"
  run "$LIBMAN_BIN_DIR/libman" update
  assert_failure
  assert_output --partial 'installation lock'
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 1.0.0 ]]
}

@test "piped bootstrap verifies the bin bundle and installs the same release" {
  run bash -c 'bash -s -- --version 1.0.0 --init-shell bash <"$1/bin/install"' _ "$REPO_ROOT"
  assert_success
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 1.0.0 ]]
  [[ $(<"$LIBSH_INSTALL_DIR.libman/manager-version") == 1.0.0 ]]
  [[ -f $HOME/.bashrc ]]
}

@test "piped bootstrap refuses a corrupt manager before executing it" {
  printf 'broken' >>"$FIXTURES/v1.0.0/libsh-bin-1.0.0.tar.gz"
  run bash -c 'bash -s -- --version 1.0.0 <"$1/bin/install"' _ "$REPO_ROOT"
  assert_failure
  assert_output --partial 'manager checksum mismatch'
  [[ ! -e $LIBSH_INSTALL_DIR.libman ]]
}

@test "scripts use explicit LIBSH_DIR and reject broken overrides" {
  install_release
  run env LIBSH_DIR="$LIBSH_INSTALL_DIR" bash "$REPO_ROOT/scripts/archive-create.sh" --help
  assert_success
  run env LIBSH_DIR="$HOME/missing" bash "$REPO_ROOT/scripts/archive-create.sh" --help
  assert_failure
  assert_output --partial 'Cannot read libsh'
  run env -u LIBSH_DIR bash "$REPO_ROOT/scripts/archive-create.sh" --help
  assert_success
}

@test "loader resolves one physical release and reports its version" {
  install_release
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  run bash -c 'source "$LIBSH_INSTALL_DIR/lib.sh"; "$LIBMAN_BIN_DIR/libman" update >/dev/null; lib::load; printf "%s\n%s" "$LIBSH_LIB_DIR" "$LIBSH_LOADED_VERSION"'
  assert_success
  assert_output "$old/lib"$'\n1.0.0'
}

@test "shell auto detection and explicit no-profile protection" {
  run env SHELL=/bin/zsh bash "$REPO_ROOT/bin/install" --version 1.0.0 --init-shell auto
  assert_success
  [[ -f $HOME/.zshrc && ! -f $HOME/.bashrc ]]
  run bash "$REPO_ROOT/bin/install" --version 1.0.0 --init-shell bash --no-modify-profile
  assert_failure
  [[ ! -f $HOME/.bashrc ]]
  run bash "$REPO_ROOT/bin/install" --version 1.0.0 --profile-targets bash_env
  assert_failure
}

@test "archive links are rejected without changing the installed release" {
  install_release
  ln -s /etc/passwd "$BATS_TEST_TMPDIR/source/lib/unsafe"
  make_release 2.0.0
  run "$LIBMAN_BIN_DIR/libman" update
  assert_failure
  assert_output --partial 'Bundle links and special files are unsupported'
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 1.0.0 ]]
}

@test "all operational scripts bootstrap from the selected library" {
  install_release --extensions apt,secret,shell,ui
  local script
  for script in "$REPO_ROOT"/scripts/*.sh; do
    run env LIBSH_DIR="$LIBSH_INSTALL_DIR" bash "$script" --help
    assert_success
  done
}

@test "uninstall requires confirmation and retains modified command paths" {
  install_release
  run "$LIBMAN_BIN_DIR/libman" uninstall </dev/null
  assert_failure
  [[ -r $LIBSH_INSTALL_DIR/lib.sh ]]
  rm "$LIBMAN_BIN_DIR/libman"
  printf 'user replacement\n' >"$LIBMAN_BIN_DIR/libman"
  run bash "$REPO_ROOT/bin/libman" uninstall --yes
  assert_failure
  [[ $(<"$LIBMAN_BIN_DIR/libman") == 'user replacement' && -r $LIBSH_INSTALL_DIR/lib.sh ]]
}

@test "latest bootstrap works without arguments and status needs no network" {
  run bash -c 'bash <"$1/bin/install"' _ "$REPO_ROOT"
  assert_success
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 2.0.0 ]]
  printf '#!/usr/bin/env bash\nexit 99\n' >"$BATS_TEST_TMPDIR/fake/curl"
  run "$LIBMAN_BIN_DIR/libman" status
  assert_success
  run "$LIBMAN_BIN_DIR/libman" path
  assert_success
}

@test "loader propagates a failed module and checkout metadata is explicit" {
  local library="$BATS_TEST_TMPDIR/custom"
  mkdir -p "$library"
  cp "$REPO_ROOT/lib/lib.sh" "$library/lib.sh"
  printf 'return 7\n' >"$library/broken.sh"
  run bash -c 'source "$1/lib.sh"' _ "$library"
  assert_failure 7
  printf '# valid module\n' >"$library/broken.sh"
  run bash -c 'source "$1/lib.sh"; printf "%s" "$LIBSH_LOADED_VERSION"' _ "$library"
  assert_success
  assert_output development
}

@test "core-only install never downloads extensions" {
  install_release
  run grep 'libsh-ext-' "$FIXTURES/downloads"
  assert_failure 1
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_success
  assert_output ''
  run bash -c 'source "$LIBSH_INSTALL_DIR/lib.sh"; lib::load_extensions secret'
  assert_failure 1
}

@test "selected addons install and load without unrelated downloads" {
  install_release --extensions secret,git
  run grep -E 'libsh-ext-(apt|ui|py|shell)-' "$FIXTURES/downloads"
  assert_failure 1
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_success
  assert_output $'secret\ngit'
  run bash -c 'source "$LIBSH_INSTALL_DIR/lib.sh"; lib::load_extensions secret git; declare -F ext::secret::resolve ext::git::toplevel'
  assert_success
}

@test "addon lifecycle pins the core and preserves selection across updates" {
  install_release --extensions secret
  local original
  original=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  run "$LIBMAN_BIN_DIR/libman" extension-add git apt
  assert_success
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 1.0.0 ]]
  [[ -r $original/extensions/libsecret.sh ]]
  run "$LIBMAN_BIN_DIR/libman" extension-remove secret
  assert_success
  run "$LIBMAN_BIN_DIR/libman" update
  assert_success
  [[ $(<"$LIBSH_INSTALL_DIR/.libsh-version") == 2.0.0 ]]
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_output $'git\napt'
  run "$LIBMAN_BIN_DIR/libman" update --extensions none
  assert_success
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_output ''
}

@test "missing and corrupted addon assets leave current release intact" {
  install_release --extensions secret
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  run "$LIBMAN_BIN_DIR/libman" extension-add missing
  assert_failure
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
  printf 'corrupt' >>"$FIXTURES/v2.0.0/libsh-ext-secret-2.0.0.tar.gz"
  run "$LIBMAN_BIN_DIR/libman" update
  assert_failure
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_output secret
  [[ ! -d $LIBSH_INSTALL_DIR.libman-lock ]]
}

@test "addon loader stays on the resolved release after update" {
  install_release --extensions secret
  run bash -c '
  source "$LIBSH_INSTALL_DIR/lib.sh"
  original=$LIBSH_LIB_DIR
  "$LIBMAN_BIN_DIR/libman" update --extensions none >/dev/null || exit
  [[ $LIBSH_LIB_DIR == "$original" && $LIBSH_LOADED_VERSION == 1.0.0 ]] || exit 1
  lib::load_extensions secret || exit
  declare -F ext::secret::resolve
 '
  assert_success
}

@test "addon names and selection are validated without downloading" {
  install_release
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  run "$LIBMAN_BIN_DIR/libman" extension-add ../secret
  assert_failure 2
  run "$LIBMAN_BIN_DIR/libman" update --extensions secret,,git
  assert_failure 2
  run "$LIBMAN_BIN_DIR/libman" extension-remove secret
  assert_failure 2
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
}

@test "piped bootstrap forwards explicit addon selection" {
  run bash -c 'cat "$1/bin/install" | bash -s -- --version 1.0.0 --extensions secret' _ "$REPO_ROOT"
  assert_success
  run "$LIBMAN_BIN_DIR/libman" extensions
  assert_output secret
}

@test "addon install environment does not override offline saved selection" {
  install_release --extensions secret
  run env LIBSH_EXTENSIONS=git "$LIBMAN_BIN_DIR/libman" extensions
  assert_success
  assert_output secret
}

@test "addon archive cannot overwrite core files even with a valid checksum" {
  install_release
  local old
  old=$(readlink "$LIBSH_INSTALL_DIR.libman/current")
  tar -czf "$FIXTURES/v1.0.0/libsh-ext-git-1.0.0.tar.gz" -C "$BATS_TEST_TMPDIR/source" lib/lib.sh
  (cd "$FIXTURES/v1.0.0" && { if command -v sha256sum >/dev/null; then sha256sum ./*.tar.gz; else shasum -a 256 ./*.tar.gz; fi; } | sed 's|  ./|  |' >CHECKSUMS_SHA256.txt)
  run "$LIBMAN_BIN_DIR/libman" extension-add git
  assert_failure
  assert_output --partial 'Unsafe bundle path'
  [[ $(readlink "$LIBSH_INSTALL_DIR.libman/current") == "$old" ]]
}

@test "scripts diagnose an old explicit installation instead of falling back" {
  local old="$BATS_TEST_TMPDIR/old-library" script
  mkdir -p "$old"
  old=$(cd -P "$old" && pwd)
  printf 'lib::lib::load() { :; }\nlib::lib::load\n' >"$old/lib.sh"
  for script in "$REPO_ROOT"/scripts/*.sh; do
    run env LIBSH_DIR="$old" bash "$script" --help
    assert_failure 1
    assert_output --partial "Incompatible libsh at $old"
    refute_output --partial 'command not found'
  done
}

@test "Ubuntu scripts can explicitly select the checkout instead of an older installation" {
  local script checkout="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$checkout"
  cp -R "$REPO_ROOT/lib/" "$checkout/lib"
  cp -R "$REPO_ROOT/extensions/" "$checkout/extensions"
  for script in ubuntu-update-packages ubuntu-update-security; do
    run env LIBSH_DIR="$checkout/lib" bash "$REPO_ROOT/scripts/$script.sh" --help
    assert_success
    assert_output --partial "Usage: $script.sh"
  done
}
