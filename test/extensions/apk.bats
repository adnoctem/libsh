#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions apk
}

@test "APK installed query accepts literal names and propagates absence" {
  # shellcheck disable=SC2329 # backend fixture
  apk() { [[ $* == 'info --exists -- lib-test2' ]]; }
  run ext::apk::is_installed lib-test2
  assert_success
  run ext::apk::is_installed absent
  assert_failure 1
  run ext::apk::is_installed 'lib*'
  assert_failure 2
}

@test "APK pending packages preserve digit-containing names and use cached versions" {
  # shellcheck disable=SC2329 # backend fixture
  apk() {
    [[ $* == 'version --limit <' && $LC_ALL == C ]] || return 1
    printf '%s\n' 'Installed: Available:' 'lib-test-2-1.0-r0 < 1.1-r1' 'musl-1.2.3-r0 < 1.2.4-r0'
  }
  run ext::apk::pending_packages
  assert_success
  assert_output $'lib-test-2\nmusl'
}

@test "APK lookup failures emit no partial package results" {
  # shellcheck disable=SC2329
  apk() {
    printf 'musl-1.0-r0 < 2.0-r0\n'
    return 1
  }
  run ext::apk::pending_packages
  assert_failure 1
  assert_output ''
  # shellcheck disable=SC2329
  apk() { :; }
  run ext::apk::pending_packages
  assert_success
  assert_output ''
}
